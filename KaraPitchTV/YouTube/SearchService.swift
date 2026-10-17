import Foundation
import SmartTubeIOSCore

struct SearchResult: Codable, Equatable, Sendable {
    let url: String
    let title: String
    var channel: String?
    var thumb: String?
    var durationSec: Int64 = 0
}

/// YouTube video search, a port of the Android `SearchService.kt`.
enum SearchService {
    static let maxResults = 20
    static let maxDurationSec: Int64 = 15 * 60

    static func search(_ query: String, addKaraoke: Bool, api: InnerTubeAPI) async throws -> [SearchResult] {
        results(from: try await api.search(query: buildQuery(query, addKaraoke: addKaraoke)).videos)
    }

    /// Appends "karaoke" unless it's off or the person already typed it.
    static func buildQuery(_ query: String, addKaraoke: Bool) -> String {
        let q = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return addKaraoke && q.range(of: "karaoke", options: .caseInsensitive) == nil ? "\(q) karaoke" : q
    }

    /// Songs only: no live streams, nothing over 15 minutes (full albums, compilations).
    static func keep(durationSec: Int64, isLive: Bool) -> Bool {
        !isLive && (1...maxDurationSec).contains(durationSec)
    }

    static func results(from videos: [Video]) -> [SearchResult] {
        Array(songs(from: videos).prefix(maxResults))
    }

    /// The songs in one page of YouTube results, without duplicates and without a cap.
    static func songs(from videos: [Video]) -> [SearchResult] {
        var seen = Set<String>()
        return videos.compactMap { video -> SearchResult? in
            let duration = Int64(video.duration ?? 0)
            guard keep(durationSec: duration, isLive: video.isLive || video.isUpcoming),
                let url = YouTubeURL.normalize("https://www.youtube.com/watch?v=\(video.id)"),
                seen.insert(url).inserted
            else { return nil }
            let meta = VideoMeta(video)
            return SearchResult(url: url, title: meta.title, channel: meta.uploader, thumb: meta.thumb, durationSec: duration)
        }
    }
}
