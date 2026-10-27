import AVFoundation
import os

/// A muted, looping video shown behind a karaoke video whose background is keyed out.
@MainActor
final class BackdropPlayer {
    /// Proof of concept: a short clip, looped.
    static let videoID = "IXbnzEHZDPg"

    let player = AVPlayer()
    private let resolver: StreamResolver
    private var loading: Task<Void, Never>?
    private var endObserver: (any NSObjectProtocol)?
    private var wanted = false

    init(resolver: StreamResolver) {
        self.resolver = resolver
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        // Loops by seeking back at the end. AVPlayerLooper never starts on these remote streams.
        player.actionAtItemEnd = .none
    }

    /// Plays the backdrop, resolving it first if it hasn't been or its URL went stale.
    func start() {
        wanted = true
        if player.currentItem == nil || player.currentItem?.status == .failed { load() }
        player.play()
    }

    func pause() {
        wanted = false
        player.pause()
    }

    private func load() {
        guard loading == nil else { return }
        loading = Task {
            defer { loading = nil }
            do {
                let streams = try await resolver.resolve(videoID: Self.videoID)
                let item = try await Self.makeItem(streams)
                endObserver.map(NotificationCenter.default.removeObserver)
                endObserver = NotificationCenter.default.addObserver(
                    forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.player.seek(to: .zero) }
                }
                player.replaceCurrentItem(with: item)
                Logger.backdrop.notice("backdrop \(Self.videoID, privacy: .public): \(streams.description, privacy: .public)")
                if wanted { player.play() }
            } catch {
                Logger.backdrop.error("backdrop load failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// The video track alone, in a composition like `KaraPlayer`'s: a plain `AVPlayerItem` of these
    /// URLs never gets past `.unknown`.
    private static func makeItem(_ streams: Streams) async throws -> AVPlayerItem {
        let options: [String: Any] = ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": streams.userAgent]]
        let asset = AVURLAsset(url: streams.videoURL, options: options)
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
