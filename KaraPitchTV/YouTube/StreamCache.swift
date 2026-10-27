import Foundation

/// Streams resolved when a song was queued, reused when it plays if they're still fresh.
actor StreamCache {
    /// googlevideo URLs last a few hours; an hour leaves plenty of margin.
    static let maxAge: Duration = .seconds(60 * 60)

    private var entries: [String: (streams: Streams, at: ContinuousClock.Instant)] = [:]

    func store(_ streams: Streams) {
        entries[streams.videoID] = (streams, .now)
    }

    /// The streams for `videoID` if they were resolved within `maxAge`.
    func fresh(_ videoID: String) -> Streams? {
        guard let entry = entries[videoID] else { return nil }
        if ContinuousClock.now - entry.at < Self.maxAge { return entry.streams }
        entries[videoID] = nil
        return nil
    }

    func remove(_ videoID: String) {
        entries[videoID] = nil
    }
}
