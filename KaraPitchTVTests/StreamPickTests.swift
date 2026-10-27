import Foundation
import SmartTubeIOSCore
import Testing
@testable import KaraPitchTV

struct StreamPickTests {
    private func format(_ mime: String, height: Int = 0, fps: Int = 30, bitrate: Int = 0, url: String? = "https://rr1.googlevideo.com/videoplayback?itag=1")
        -> VideoFormat
    {
        VideoFormat(label: "\(height)p", width: 0, height: height, fps: fps, mimeType: mime, url: url.flatMap(URL.init(string:)), bitrate: bitrate)
    }

    private let avc1080 = #"video/mp4; codecs="avc1.640028""#
    private let aac = #"audio/mp4; codecs="mp4a.40.2""#

    @Test func picksBestAvcUpTo1080pAndBestAac() throws {
        let formats = [
            format(avc1080, height: 720, bitrate: 2_000_000),
            format(avc1080, height: 1080, bitrate: 4_000_000),
            format(avc1080, height: 1440, bitrate: 9_000_000),
            format(#"video/webm; codecs="vp9""#, height: 1080, bitrate: 5_000_000),
            format(#"video/mp4; codecs="av01.0.08M.08""#, height: 1080, bitrate: 3_000_000),
            format(aac, bitrate: 48_000),
            format(aac, bitrate: 128_000),
            format(#"audio/webm; codecs="opus""#, bitrate: 160_000),
        ]
        let pick = try #require(StreamResolver.pick(formats))
        #expect(pick.video.height == 1080)
        #expect(pick.video.mimeType.contains("avc1"))
        #expect(pick.audio?.bitrate == 128_000)
    }

    @Test func prefersHigherFpsAtSameHeight() throws {
        let pick = try #require(StreamResolver.pick([format(avc1080, height: 1080, fps: 30), format(avc1080, height: 1080, fps: 60), format(aac)]))
        #expect(pick.video.fps == 60)
    }

    @Test func fallsBackToMuxedWithoutAdaptiveAudio() throws {
        let muxed = format(#"video/mp4; codecs="avc1.42001E, mp4a.40.2""#, height: 360)
        let pick = try #require(StreamResolver.pick([format(avc1080, height: 1080), muxed]))
        #expect(pick.audio == nil)
        #expect(pick.video == muxed)
    }

    @Test func ignoresFormatsWithoutDirectURLs() {
        let formats = [
            format(avc1080, height: 1080, url: nil),
            format(aac, url: nil),
            format(avc1080, height: 720, url: "https://rr1.googlevideo.com/videoplayback?c=TVHTML5&itag=136"),
            format(#"video/mp4; codecs="avc1.42001E, mp4a.40.2""#, height: 360, url: "https://manifest.googlevideo.com/api/manifest/hls_playlist/x.m3u8"),
        ]
        #expect(StreamResolver.pick(formats) == nil)
    }

    @Test func acceptsRqhURLs() {
        let rqh = "https://rr1.googlevideo.com/videoplayback?rqh=1&itag=137"
        #expect(StreamResolver.pick([format(avc1080, height: 1080, url: rqh), format(aac, url: rqh)]) != nil)
    }

    @Test func nothingPlayableReturnsNil() {
        #expect(StreamResolver.pick([format(#"video/webm; codecs="vp9""#, height: 1080), format(#"audio/webm; codecs="opus""#)]) == nil)
    }
}

/// Phase 1a against the live network. Run with `TEST_RUNNER_KARA_PROBE=1 xcodebuild test …`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["KARA_PROBE"] == "1"), .timeLimit(.minutes(10)))
struct StreamProbeLiveTests {
    @Test func someClientServesDirectStreamsForMostVideos() async throws {
        let api = InnerTubeAPI()
        let ids = try await StreamProbe.karaokeVideoIDs(api: api)
        try #require(ids.count >= 5, "search returned too few videos")
        let rows = await StreamProbe.run(videoIDs: ids, api: api)
        for row in rows { print(row.summary) }
        let summary = StreamProbe.summary(rows)
        for line in summary { print("PROBE \(line.client.rawValue): usable for \(line.usable)/\(line.total)") }
        let best = summary.map(\.usable).max() ?? 0
        #expect(best * 2 > ids.count, "no client was usable for most videos")
    }
}
