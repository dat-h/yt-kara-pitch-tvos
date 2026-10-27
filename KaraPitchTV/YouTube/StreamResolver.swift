import Foundation
import SmartTubeIOSCore
import os

/// Media URLs for one playback. `audioURL` is nil when `videoURL` already carries the audio.
struct Streams: Sendable {
    let videoID: String
    let videoURL: URL
    let audioURL: URL?
    let client: StreamClient
    let description: String

    /// googlevideo URLs are signed for the client that requested them; fetch them with its UA.
    var userAgent: String { client.userAgent }
}

/// InnerTube clients that need neither a PoToken nor WKWebView.
enum StreamClient: String, CaseIterable, Sendable {
    case visionOS, androidVR, android, tvEmbedded

    /// The order `StreamResolver` tries them in. From the Phase 1a probe (2026-10-16): visionOS
    /// 10/10 and androidVR 9/10 at 1080p, android 10/10 but only 360p muxed, tvEmbedded 0/10.
    static let resolveOrder: [StreamClient] = [.visionOS, .androidVR, .android]

    /// Copied from SmartTubeIOSCore's `InnerTubeClients.swift`, where they're `package`-scoped.
    /// Update these together with the SmartTubeIOS pin.
    var userAgent: String {
        switch self {
        case .visionOS:
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15"
        case .androidVR:
            "com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip"
        case .tvEmbedded:
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        case .android:
            "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip"
        }
    }

    func fetch(_ api: InnerTubeAPI, videoID: String) async throws -> PlayerInfo {
        switch self {
        case .visionOS: try await api.fetchPlayerInfoVisionOS(videoId: videoID)
        case .androidVR: try await api.fetchPlayerInfoAndroidVR(videoId: videoID)
        case .android: try await api.fetchPlayerInfoAndroid(videoId: videoID)
        case .tvEmbedded: try await api.fetchPlayerInfoTVEmbedded(videoId: videoID)
        }
    }
}

/// The formats chosen for one playback. `audio` is nil for a muxed `video`.
struct StreamPick: Equatable, Sendable {
    let video: VideoFormat
    let audio: VideoFormat?

    var description: String {
        if let audio {
            "\(video.height)p \(Self.codec(video)) + \(Self.codec(audio)) \((audio.bitrate ?? 0) / 1000)k"
        } else {
            "\(video.height)p muxed \(Self.codec(video))"
        }
    }

    private static func codec(_ f: VideoFormat) -> String {
        f.mimeType.components(separatedBy: "codecs=").last?.trimmingCharacters(in: CharacterSet(charactersIn: "\" ")) ?? f.mimeType
    }
}

enum StreamResolverError: Error, CustomStringConvertible {
    case noPlayableStream(videoID: String, attempts: [String])

    var description: String {
        switch self {
        case let .noPlayableStream(videoID, attempts):
            "No playable MP4 stream for \(videoID): \(attempts.joined(separator: "; "))"
        }
    }
}

/// Resolved fresh for every play: googlevideo URLs expire after a few hours.
struct StreamResolver: Sendable {
    static let maxHeight = 1080

    let api: InnerTubeAPI
    var clients: [StreamClient] = StreamClient.resolveOrder

    func resolve(videoID: String) async throws -> Streams {
        var attempts: [String] = []
        for client in clients {
            do {
                let info = try await client.fetch(api, videoID: videoID)
                guard let pick = Self.pick(info.formats) else {
                    attempts.append("\(client.rawValue): no direct avc1/mp4a")
                    Logger.resolver.notice("\(videoID, privacy: .public) \(client.rawValue, privacy: .public): no usable formats of \(info.formats.count)")
                    continue
                }
                guard let videoURL = pick.video.url else { continue }
                Logger.resolver.notice("\(videoID, privacy: .public) \(client.rawValue, privacy: .public): \(pick.description, privacy: .public)")
                return Streams(videoID: videoID, videoURL: videoURL, audioURL: pick.audio?.url, client: client, description: pick.description)
            } catch {
                attempts.append("\(client.rawValue): \(error)")
                Logger.resolver.notice("\(videoID, privacy: .public) \(client.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
        throw StreamResolverError.noPlayableStream(videoID: videoID, attempts: attempts)
    }

    /// Title, channel, thumbnail and length for a pasted link, from the first client that answers.
    func meta(videoID: String) async throws -> VideoMeta {
        var attempts: [String] = []
        for client in clients {
            do {
                return VideoMeta(try await client.fetch(api, videoID: videoID).video)
            } catch {
                attempts.append("\(client.rawValue): \(error)")
            }
        }
        throw StreamResolverError.noPlayableStream(videoID: videoID, attempts: attempts)
    }

    /// The best `avc1` video-only MP4 up to 1080p plus the best AAC audio-only M4A, else the best
    /// muxed `avc1`+`mp4a` MP4. AVFoundation can't play VP9, WebM or AV1 here, and HLS defeats the
    /// audio tap, so neither is ever picked.
    static func pick(_ formats: [VideoFormat]) -> StreamPick? {
        let direct = formats.filter(isDirect)
        let video = direct
            .filter { isMP4Video($0) && !isMuxed($0) && $0.mimeType.contains("avc1") && (1...maxHeight).contains($0.height) }
            .max { ($0.height, $0.fps, $0.bitrate ?? 0) < ($1.height, $1.fps, $1.bitrate ?? 0) }
        let audio = direct
            .filter { $0.mimeType.hasPrefix("audio/mp4") && $0.mimeType.contains("mp4a") }
            .max { ($0.bitrate ?? 0) < ($1.bitrate ?? 0) }
        if let video, let audio { return StreamPick(video: video, audio: audio) }

        let muxed = direct
            .filter { isMP4Video($0) && isMuxed($0) && $0.mimeType.contains("avc1") && $0.mimeType.contains("mp4a") && $0.height <= maxHeight }
            .max { ($0.height, $0.bitrate ?? 0) < ($1.height, $1.bitrate ?? 0) }
        return muxed.map { StreamPick(video: $0, audio: nil) }
    }

    /// A plain progressive URL: not an HLS/DASH manifest and not SABR (`c=TVHTML5`).
    ///
    /// SmartTube treats `rqh=1` URLs as stalling, but the Phase 1a probe got full 128 KB ranges
    /// from all of them when fetched with the issuing client's User-Agent, so they're allowed.
    static func isDirect(_ format: VideoFormat) -> Bool { rejection(format) == nil }

    /// Why `format` isn't a plain progressive URL, or nil when it is.
    static func rejection(_ format: VideoFormat) -> String? {
        guard let url = format.url?.absoluteString else { return "no url" }
        return [".m3u8", "/manifest/", "c=TVHTML5"].first { url.contains($0) }
    }

    private static func isMP4Video(_ f: VideoFormat) -> Bool { f.mimeType.hasPrefix("video/mp4") }

    /// Muxed formats list two codecs, e.g. `codecs="avc1.42001E, mp4a.40.2"`.
    private static func isMuxed(_ f: VideoFormat) -> Bool { f.mimeType.contains(",") }
}

extension VideoMeta {
    init(_ video: Video) {
        self.init(
            title: video.title,
            uploader: video.channelTitle.isEmpty ? nil : video.channelTitle,
            thumb: (video.thumbnailURL ?? URL(string: "https://i.ytimg.com/vi/\(video.id)/hqdefault.jpg"))?.absoluteString,
            durationSec: Int64(video.duration ?? 0)
        )
    }
}
