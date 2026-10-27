import AVFoundation
import Observation
import os

/// The song's music video, muted and looping behind a karaoke video whose background is keyed out.
@MainActor @Observable
final class BackdropPlayer {
    let player = AVPlayer()
    /// The prepared video has frames to show; until then the karaoke video plays as it is.
    private(set) var isReady = false
    /// The music video prepared or being prepared.
    private(set) var videoID: String?

    @ObservationIgnored private var wanted = false
    @ObservationIgnored private var loading: Task<Void, Never>?
    @ObservationIgnored private var statusObservation: NSKeyValueObservation?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    init() {
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        // Loops by seeking back at the end. AVPlayerLooper never starts on these remote streams.
        player.actionAtItemEnd = .none
    }

    /// Loads `streams` (a music video's) in the background, replacing whatever was prepared.
    func prepare(_ streams: Streams) {
        guard streams.videoID != videoID else { return }
        stop()
        videoID = streams.videoID
        loading = Task {
            do {
                let item = try await Self.makeItem(streams)
                guard !Task.isCancelled, videoID == streams.videoID else { return }
                install(item)
                Logger.backdrop.notice("backdrop \(streams.videoID, privacy: .public): \(streams.description, privacy: .public)")
            } catch {
                Logger.backdrop.error("backdrop \(streams.videoID, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Plays the prepared video, now or as soon as it's loaded.
    func play() {
        wanted = true
        player.play()
    }

    func pause() {
        wanted = false
        player.pause()
    }

    /// Drops the prepared video.
    func stop() {
        loading?.cancel()
        loading = nil
        wanted = false
        statusObservation = nil
        endObserver.map(NotificationCenter.default.removeObserver)
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
        isReady = false
        videoID = nil
    }

    private func install(_ item: AVPlayerItem) {
        endObserver = NotificationCenter.default.addObserver(forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.player.seek(to: .zero) }
        }
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            let ready = item.status == .readyToPlay
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                self.isReady = ready
            }
        }
        player.replaceCurrentItem(with: item)
        if wanted { player.play() }
    }

    /// The video track alone, in a composition like `KaraPlayer`'s: a plain `AVPlayerItem` of these
    /// URLs never gets past `.unknown`.
    private static func makeItem(_ streams: Streams) async throws -> AVPlayerItem {
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": streams.userAgent]]
        let asset = AVURLAsset(url: streams.videoURL, options: options)
        // A very long video can take minutes to open; give up like a song would.
        let timeout = Task {
            try await Task.sleep(for: KaraPlayer.loadTimeout)
            asset.cancelLoading()
        }
        defer { timeout.cancel() }
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw PlayerError.missingTrack }
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        guard let compVideo = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw PlayerError.missingTrack }
        try compVideo.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: track, at: .zero)
        compVideo.preferredTransform = try await track.load(.preferredTransform)
        return AVPlayerItem(asset: composition)
    }
}
