import Foundation
import SmartTubeIOSCore
import os

/// Searches YouTube for a karaoke song's music video and keeps the first good match that resolves.
struct MusicVideoFinder: Sendable {
    let api: InnerTubeAPI
    let resolver: StreamResolver
    let cache: StreamCache

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

    /// The first candidate that resolves, with its streams cached for when the song plays.
    func find(for entry: QueueEntry) async -> MusicVideo? {
        let ranked: [MusicVideoCandidate]
        do {
            ranked = try await candidates(for: entry)
        } catch {
            Logger.resolver.notice("music video search failed for \(entry.title, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
        for candidate in ranked {
            guard let streams = try? await resolver.resolve(videoID: candidate.id) else { continue }
            await cache.store(streams)
            Logger.resolver.notice("music video for \(entry.title, privacy: .public): \(candidate.id, privacy: .public) \(candidate.title, privacy: .public)")
            return MusicVideo(url: "https://www.youtube.com/watch?v=\(candidate.id)", title: candidate.title, channel: candidate.channel)
        }
        Logger.resolver.notice("no music video for \(entry.title, privacy: .public) (\(ranked.count) candidates)")
        return nil
    }
}
