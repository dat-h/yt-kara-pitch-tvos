import AVFoundation
import Foundation
import SmartTubeIOSCore
import Testing
@testable import KaraPitchTV

/// Checks one video against the live network before it's used in the app: does it resolve, and
/// does AVFoundation load its video track in time? Run with `sh scripts/check-stream.sh <url>`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["KARA_CHECK_URL"] != nil), .timeLimit(.minutes(2)))
struct StreamCheckLiveTests {
    /// With `--music`: the music video the app would pair with this karaoke video, and the runners-up.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KARA_CHECK_MUSIC"] == "1"))
    func findsTheMusicVideo() async throws {
        let env = ProcessInfo.processInfo.environment
        var report: [String] = []
        defer {
            let text = report.joined(separator: "\n") + "\n"
            if let out = env["KARA_CHECK_OUT"] { try? text.write(toFile: out, atomically: true, encoding: .utf8) }
        }
        let url = env["KARA_CHECK_URL"] ?? ""
        let api = InnerTubeAPI()
        let resolver = StreamResolver(api: api)
        guard let normalized = YouTubeURL.normalize(url), let id = YouTubeURL.videoID(of: url),
            let meta = try? await resolver.resolveWithMeta(videoID: id).meta
        else {
            report.append("❌ couldn't resolve the karaoke video \(url)")
            Issue.record("karaoke video didn't resolve")
            return
        }
        var entry = QueueEntry(id: "check", url: normalized)
        entry.title = meta.title
        entry.durationSec = meta.durationSec
        report.append("karaoke: \(meta.title) (\(meta.durationSec) s)")
        report.append("search: \(MusicVideoMatcher.searchQuery(fromKaraokeTitle: meta.title))")

        let finder = MusicVideoFinder(api: api, block: resolver.block)
        let candidates = try await finder.candidates(for: entry)
        for (i, c) in candidates.enumerated() { report.append("  \(i + 1). \(c.id) \(c.title) · \(c.channel) · \(c.durationSec) s") }
        // What the app does when the song is about to play: the first that resolves.
        for c in candidates {
            if (try? await resolver.resolve(videoID: c.id)) != nil {
                report.append("✅ music video: \(c.title) · \(c.channel) · \(MusicVideoFinder.watchURL(c.id))")
                return
            }
            report.append("   \(c.id) doesn't resolve, trying the next")
        }
        report.append("➖ no music video: the song would play as plain karaoke")
    }

    static let loadTimeout: Duration = .seconds(20)

    @Test func resolvesAndLoads() async throws {
        let env = ProcessInfo.processInfo.environment
        var report: [String] = []
        defer {
            let text = report.joined(separator: "\n") + "\n"
            if let out = env["KARA_CHECK_OUT"] { try? text.write(toFile: out, atomically: true, encoding: .utf8) }
        }

        let url = env["KARA_CHECK_URL"] ?? ""
        guard let id = YouTubeURL.videoID(of: url) else {
            report.append("❌ not a YouTube video link: \(url)")
            Issue.record("not a YouTube video link")
            return
        }
        report.append("video \(id)")

        let streams: Streams
        do {
            streams = try await StreamResolver(api: InnerTubeAPI()).resolve(videoID: id)
        } catch {
            report.append("❌ resolve: \(error)")
            Issue.record("resolve failed")
            return
        }
        let query = URLComponents(url: streams.videoURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func param(_ name: String) -> String { query.first { $0.name == name }?.value ?? "?" }
        let megabytes = Double(param("clen")).map { String(format: "%.1f MB", $0 / 1_000_000) } ?? "?"
        report.append("✅ resolve: \(streams.client.rawValue), \(streams.description), \(param("dur")) s, video \(megabytes)")

        // What BackdropPlayer and KaraPlayer do first: load the video track and the duration.
        let asset = AVURLAsset(url: streams.videoURL, options: ["AVURLAssetHTTPHeaderFieldsKey": ["User-Agent": streams.userAgent]])
        let timeout = Task {
            try await Task.sleep(for: Self.loadTimeout)
            asset.cancelLoading()
        }
        defer { timeout.cancel() }
        let start = ContinuousClock.now
        do {
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let duration = try await asset.load(.duration)
            try #require(!tracks.isEmpty, "no video track")
            report.append("✅ load: video track and \(Int(duration.seconds)) s duration in \(ContinuousClock.now - start)")
        } catch {
            report.append("❌ load after \(ContinuousClock.now - start) (timeout \(Self.loadTimeout)): \(error.localizedDescription)")
            Issue.record("load failed")
        }
    }
}
