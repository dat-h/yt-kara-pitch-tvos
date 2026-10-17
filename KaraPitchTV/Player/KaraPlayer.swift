import AVFoundation
import Observation
import os

/// What the phone UI and the TV screens see of the player (`/api/state?player=1`).
struct PlayerSnapshot: Codable, Equatable, Sendable {
    var positionMs: Int64 = 0
    var durationMs: Int64 = 0
    var paused = false
    var buffering = false
    var key = 0
}

enum Outcome: Equatable, Sendable {
    case ended
    case skipped
    /// The player went away (the app left the screen) mid-song.
    case released
    case error(httpCode: Int?, position: Double, message: String?)
}

/// AVPlayer for one song at a time, with the key in semitones (Approach A in ADR 0001): the two
/// streams in one composition, the audio through `PitchTap`. A port of the Android `KaraPlayer.kt`.
@MainActor @Observable
final class KaraPlayer {
    /// How long AVFoundation gets to open both streams before the song counts as failed.
    static let loadTimeout: Duration = .seconds(15)

    let player = AVPlayer()
    private(set) var snapshot = PlayerSnapshot()
    private(set) var key = 0

    @ObservationIgnored private var tapContext = PitchTapContext()
    @ObservationIgnored private var current: CheckedContinuation<Outcome, Never>?
    @ObservationIgnored private var streams: Streams?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var timeObserver: Any?
    /// Set while the app is off screen, so a song that finishes loading then doesn't start.
    @ObservationIgnored private var isReleased = false

    init() {
        player.automaticallyWaitsToMinimizeStalling = true
        timeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 2), queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    /// Plays `streams` from `startAt` seconds at `startKey`, and returns once the song is over.
    func play(_ streams: Streams, startKey: Int, startAt: Double = 0) async -> Outcome {
        finish(.skipped)  // never two songs at once
        guard !isReleased else { return .released }
        self.streams = streams
        setKey(startKey)
        let item: AVPlayerItem
        do {
            item = try await makeItem(streams)
        } catch {
            let code = await Self.httpStatus(streams.videoURL, userAgent: streams.userAgent)
            Logger.player.error("load failed (HTTP \(code ?? 0)): \(String(describing: error), privacy: .public)")
            return .error(httpCode: code, position: startAt, message: error.localizedDescription)
        }
        guard !isReleased else { return .released }
        return await withCheckedContinuation { continuation in
            current = continuation
            observe(item)
            player.replaceCurrentItem(with: item)
            if startAt > 0 {
                player.seek(to: CMTime(seconds: startAt, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
            }
            player.play()
            publish()
        }
    }

    func setKey(_ semitones: Int) {
        key = Key.clamp(semitones)
        tapContext.semitones.store(Int32(key), ordering: .relaxed)
        publish()
    }

    func adjustKey(_ delta: Int) { setKey(key + delta) }

    func togglePause() {
        if player.rate == 0 { player.play() } else { player.pause() }
        publish()
    }

    func seek(by seconds: Double) {
        let duration = player.currentItem?.duration.seconds ?? .infinity
        let target = min(max(0, player.currentTime().seconds + seconds), max(0, (duration.isFinite ? duration : .infinity) - 1))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
        publish()
    }

    /// From the start, at the same key.
    func restart() {
        player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        player.play()
    }

    func skip() { finish(.skipped) }

    /// Stops the song because the app is leaving the screen; the session puts it back in the queue.
    /// Nothing plays again until `reattach()`.
    func release() {
        isReleased = true
        finish(.released)
    }

    func reattach() { isReleased = false }

    private func finish(_ outcome: Outcome) {
        takeCurrent()?.resume(returning: outcome)
    }

    /// Ends the current song's playback and hands back whoever is waiting on it.
    private func takeCurrent() -> CheckedContinuation<Outcome, Never>? {
        guard let continuation = current else { return nil }
        current = nil
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        player.pause()
        player.replaceCurrentItem(with: nil)
        publish()
        return continuation
    }

    private func observe(_ item: AVPlayerItem) {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.finish(.ended) }
            },
            center.addObserver(forName: AVPlayerItem.failedToPlayToEndTimeNotification, object: item, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.failed() }
            },
        ]
    }

    /// Half-second heartbeat: refreshes the snapshot and catches items that failed outright.
    private func tick() {
        if current != nil, player.currentItem?.status == .failed { failed() }
        publish()
    }

    private func failed() {
        let item = player.currentItem
        let seconds = player.currentTime().seconds
        let position = seconds.isFinite ? seconds : 0
        let logged = item?.errorLog()?.events.last.map(\.errorStatusCode).flatMap { $0 >= 400 ? $0 : nil }
        let message = item?.error?.localizedDescription
        let streams = self.streams
        guard let continuation = takeCurrent() else { return }
        Task {
            // AVFoundation rarely reports the HTTP status; ask the CDN so an expired URL gets retried.
            var code = logged
            if code == nil, let streams { code = await Self.httpStatus(streams.videoURL, userAgent: streams.userAgent) }
            Logger.player.error("playback failed (HTTP \(code ?? 0)): \(message ?? "?", privacy: .public)")
            continuation.resume(returning: .error(httpCode: code, position: position, message: message))
        }
    }

    private func publish() {
        let item = player.currentItem
        let position = player.currentTime().seconds
        let duration = item?.duration.seconds ?? 0
        snapshot = PlayerSnapshot(
            positionMs: Int64((position.isFinite ? max(0, position) : 0) * 1000),
            durationMs: Int64((duration.isFinite ? max(0, duration) : 0) * 1000),
            paused: item != nil && player.timeControlStatus == .paused,
            buffering: player.timeControlStatus == .waitingToPlayAtSpecifiedRate,
            key: key
        )
    }

    private func makeItem(_ streams: Streams) async throws -> AVPlayerItem {
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": streams.userAgent]]
        let videoAsset = AVURLAsset(url: streams.videoURL, options: options)
        let audioAsset = streams.audioURL.map { AVURLAsset(url: $0, options: options) } ?? videoAsset

        // Loading can stall on a misbehaving CDN; cancel it so the song fails instead of hanging.
        let timeout = Task {
            try await Task.sleep(for: Self.loadTimeout)
            videoAsset.cancelLoading()
            audioAsset.cancelLoading()
        }
        defer { timeout.cancel() }

        guard let videoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
            let audioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first
        else { throw PlayerError.missingTrack }
        let duration = min(try await videoAsset.load(.duration), try await audioAsset.load(.duration))
        let range = CMTimeRange(start: .zero, duration: duration)

        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let compAudio = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw PlayerError.missingTrack }
        try compVideo.insertTimeRange(range, of: videoTrack, at: .zero)
        compVideo.preferredTransform = try await videoTrack.load(.preferredTransform)
        try compAudio.insertTimeRange(range, of: audioTrack, at: .zero)

        // A fresh context per item: the old tap may still be finalizing on its own thread.
        tapContext = PitchTapContext()
        tapContext.semitones.store(Int32(key), ordering: .relaxed)
        let item = AVPlayerItem(asset: composition)
        item.audioMix = PitchTap.makeAudioMix(for: compAudio, context: tapContext)
        return item
    }

    /// The status a one-byte range request gets, to tell an expired URL (403/410) from other failures.
    private static func httpStatus(_ url: URL, userAgent: String) async -> Int? {
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("bytes=0-0", forHTTPHeaderField: "Range")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let response = try? await URLSession.shared.data(for: request).1
        return (response as? HTTPURLResponse)?.statusCode
    }
}

enum PlayerError: Error {
    case missingTrack
}
