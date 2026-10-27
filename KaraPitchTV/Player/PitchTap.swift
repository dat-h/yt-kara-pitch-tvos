import AVFoundation
import AudioToolbox
import MediaToolbox
import Synchronization
import os

/// State shared between the main actor and the audio tap's real-time thread.
///
/// The atomics are the only fields the main actor touches. Everything else is owned by the tap:
/// MediaToolbox serializes `prepare`, `process` and `unprepare`, so they never race each other.
final class PitchTapContext: @unchecked Sendable {
    /// The key to apply, in semitones. Written by the main actor, read once per buffer.
    let semitones = Atomic<Int32>(0)
    /// Source time of the last audio pulled through the tap, in microseconds (for the HUD).
    let sourceTimeMicros = Atomic<Int64>(-1)
    /// Time spent in `process` relative to the buffer's duration, in permille (for the HUD).
    let loadPermille = Atomic<Int32>(0)
    /// The `OSStatus` from setting up NewTimePitch in `prepare`; 0 means the tap is live.
    let prepareStatus = Atomic<Int32>(Int32.min)
    /// Buffers rendered since the item started; shows that the tap runs at all.
    let processCount = Atomic<Int64>(0)

    fileprivate var audioUnit: AudioUnit?
    fileprivate var appliedSemitones: Int32 = 0
    fileprivate var sampleRate: Double = 44_100
    fileprivate var sampleTime: Double = 0
}

enum PitchTap {
    /// An audio mix that runs `track` through NewTimePitch at the key in `context`.
    static func makeAudioMix(for track: AVAssetTrack, context: PitchTapContext) -> AVAudioMix? {
        var callbacks = MTAudioProcessingTapCallbacks(
            version: kMTAudioProcessingTapCallbacksVersion_0,
            clientInfo: Unmanaged.passRetained(context).toOpaque(),
            init: tapInit,
            finalize: tapFinalize,
            prepare: tapPrepare,
            unprepare: tapUnprepare,
            process: tapProcess
        )
        var tap: MTAudioProcessingTap?
        let status = MTAudioProcessingTapCreate(kCFAllocatorDefault, &callbacks, kMTAudioProcessingTapCreationFlag_PostEffects, &tap)
        guard status == noErr, let tap else {
            Logger.player.error("MTAudioProcessingTapCreate failed: \(status)")
            Unmanaged<PitchTapContext>.fromOpaque(callbacks.clientInfo!).release()
            return nil
        }
        let params = AVMutableAudioMixInputParameters(track: track)
        params.audioTapProcessor = tap
        let mix = AVMutableAudioMix()
        mix.inputParameters = [params]
        return mix
    }
}

// MARK: - Tap callbacks (C function pointers: no captures, no allocation in `process`)

private func context(of tap: MTAudioProcessingTap) -> PitchTapContext {
    Unmanaged<PitchTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).takeUnretainedValue()
}

private let tapInit: MTAudioProcessingTapInitCallback = { _, clientInfo, storageOut in
    storageOut.pointee = clientInfo
}

private let tapFinalize: MTAudioProcessingTapFinalizeCallback = { tap in
    Unmanaged<PitchTapContext>.fromOpaque(MTAudioProcessingTapGetStorage(tap)).release()
}

private let tapPrepare: MTAudioProcessingTapPrepareCallback = { tap, maxFrames, processingFormat in
    let ctx = context(of: tap)
    var format = processingFormat.pointee
    ctx.sampleRate = format.mSampleRate
    ctx.sampleTime = 0

    var description = AudioComponentDescription(
        componentType: kAudioUnitType_FormatConverter,
        componentSubType: kAudioUnitSubType_NewTimePitch,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0,
        componentFlagsMask: 0
    )
    guard let component = AudioComponentFindNext(nil, &description) else {
        ctx.prepareStatus.store(-1, ordering: .relaxed)
        return
    }
    var unit: AudioUnit?
    var status = AudioComponentInstanceNew(component, &unit)
    guard status == noErr, let unit else {
        ctx.prepareStatus.store(status, ordering: .relaxed)
        return
    }

    let formatSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
    var frames = UInt32(maxFrames)
    var callback = AURenderCallbackStruct(inputProc: renderSource, inputProcRefCon: Unmanaged.passUnretained(tap).toOpaque())
    status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, formatSize)
    if status == noErr {
        status = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, formatSize)
    }
    if status == noErr {
        status = AudioUnitSetProperty(
            unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &frames, UInt32(MemoryLayout<UInt32>.size))
    }
    if status == noErr {
        status = AudioUnitSetProperty(
            unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size))
    }
    if status == noErr { status = AudioUnitInitialize(unit) }
    guard status == noErr else {
        AudioComponentInstanceDispose(unit)
        ctx.prepareStatus.store(status, ordering: .relaxed)
        return
    }
    ctx.appliedSemitones = 0
    ctx.audioUnit = unit
    ctx.prepareStatus.store(noErr, ordering: .relaxed)
}

private let tapUnprepare: MTAudioProcessingTapUnprepareCallback = { tap in
    let ctx = context(of: tap)
    if let unit = ctx.audioUnit {
        AudioUnitUninitialize(unit)
        AudioComponentInstanceDispose(unit)
    }
    ctx.audioUnit = nil
    ctx.prepareStatus.store(Int32.min, ordering: .relaxed)
}

private let tapProcess: MTAudioProcessingTapProcessCallback = { tap, frameCount, _, bufferList, frameCountOut, flagsOut in
    let ctx = context(of: tap)
    guard let unit = ctx.audioUnit else {
        // NewTimePitch didn't come up: pass the audio through untouched.
        MTAudioProcessingTapGetSourceAudio(tap, frameCount, bufferList, flagsOut, nil, frameCountOut)
        return
    }
    let started = DispatchTime.now().uptimeNanoseconds

    let semitones = ctx.semitones.load(ordering: .relaxed)
    if semitones != ctx.appliedSemitones {
        AudioUnitSetParameter(unit, kNewTimePitchParam_Pitch, kAudioUnitScope_Global, 0, Key.cents(Int(semitones)), 0)
        ctx.appliedSemitones = semitones
    }

    var renderFlags = AudioUnitRenderActionFlags()
    var timeStamp = AudioTimeStamp()
    timeStamp.mSampleTime = ctx.sampleTime
    timeStamp.mFlags = .sampleTimeValid
    let status = AudioUnitRender(unit, &renderFlags, &timeStamp, 0, UInt32(frameCount), bufferList)
    frameCountOut.pointee = status == noErr ? frameCount : 0
    ctx.sampleTime += Double(frameCount)

    let spent = Double(DispatchTime.now().uptimeNanoseconds - started)
    let budget = Double(frameCount) / ctx.sampleRate * 1e9
    ctx.loadPermille.store(Int32(spent / budget * 1000), ordering: .relaxed)
    ctx.processCount.add(1, ordering: .relaxed)
}

/// NewTimePitch's input: pulls source audio from the tap. `refCon` is the unretained tap.
private let renderSource: AURenderCallback = { refCon, _, _, _, frameCount, bufferList in
    guard let bufferList else { return kAudio_ParamError }
    let tap = Unmanaged<MTAudioProcessingTap>.fromOpaque(refCon).takeUnretainedValue()
    var timeRange = CMTimeRange()
    var framesOut: CMItemCount = 0
    let status = MTAudioProcessingTapGetSourceAudio(tap, CMItemCount(frameCount), bufferList, nil, &timeRange, &framesOut)
    if status == noErr, timeRange.start.isNumeric {
        context(of: tap).sourceTimeMicros.store(Int64(timeRange.start.seconds * 1e6), ordering: .relaxed)
    }
    return status
}
