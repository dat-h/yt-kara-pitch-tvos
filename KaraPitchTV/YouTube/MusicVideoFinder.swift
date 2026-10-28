import Foundation
import SmartTubeIOSCore
import os

/// Searches YouTube for a karaoke song's music video. One search per song: the matches aren't
/// resolved until the song is about to play, so a busy queue doesn't trip YouTube's bot check.
struct MusicVideoFinder: Sendable {
    let api: InnerTubeAPI
    let block: NetworkBlock

    /// The best candidates for `entry`, in the order they'd be tried.
    func candidates(for entry: QueueEntry) async throws -> [MusicVideoCandidate] {
        let query = MusicVideoMatcher.searchQuery(fromKaraokeTitle: entry.title)
        let videos = try await api.search(query: query).videos
        let candidates = videos.map {
            MusicVideoCandidate(
                id: $0.id, title: $0.title, channel: $0.channelTitle, durationSec: Int64($0.duration ?? 0),
                isLive: $0.isLive || $0.isUpcoming, isShort: $0.isShort)
        }
        return MusicVideoMatcher.rank(
            candidates, karaokeTitle: entry.title, karaokeID: YouTubeURL.videoID(of: entry.url) ?? "", karaokeDurationSec: entry.durationSec)
    }

    /// The best match, with the runners-up as fallbacks; nil when there's none, or YouTube is
    /// blocking this network.
    func find(for entry: QueueEntry) async -> MusicVideo? {
        guard await !block.isBlocked else {
            Logger.resolver.notice("music video search skipped for \(entry.title, privacy: .public): network blocked")
            return nil
        }
        let ranked: [MusicVideoCandidate]
        do {
            ranked = try await candidates(for: entry)
        } catch {
            Logger.resolver.notice("music video search failed for \(entry.title, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
        guard let best = ranked.first else {
            Logger.resolver.notice("no music video for \(entry.title, privacy: .public)")
            return nil
        }
        Logger.resolver.notice("music video for \(entry.title, privacy: .public): \(best.id, privacy: .public) \(best.title, privacy: .public)")
        let fallbacks = ranked.dropFirst().map { Self.watchURL($0.id) }
        return MusicVideo(url: Self.watchURL(best.id), title: best.title, channel: best.channel, fallbacks: fallbacks.isEmpty ? nil : fallbacks)
    }

    static func watchURL(_ id: String) -> String { "https://www.youtube.com/watch?v=\(id)" }
}
