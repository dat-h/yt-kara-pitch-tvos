import Foundation

enum EntryStatus: String, Codable, Sendable {
    case resolving = "RESOLVING"
    case ready = "READY"
    case error = "ERROR"
}

struct QueueEntry: Codable, Equatable, Identifiable, Sendable {
    let id: String
    /// The canonical watch URL (see `YouTubeURL.normalize`).
    let url: String
    var title = "Loading…"
    var uploader: String?
    var thumb: String?
    var durationSec: Int64 = 0
    var singer = ""
    /// Semitones, applied when the song starts.
    var presetKey = 0
    var status = EntryStatus.resolving
    var error: String?
}

/// What a URL resolves to before it is ever played.
struct VideoMeta: Equatable, Sendable {
    let title: String
    let uploader: String?
    let thumb: String?
    let durationSec: Int64
}

struct QueueState: Codable, Equatable, Sendable {
    /// Bumped on every change to `nowPlaying` or `queue`; clients poll with it.
    var version: Int64 = 0
    var nowPlaying: QueueEntry?
    var queue: [QueueEntry] = []

    func firstReady() -> QueueEntry? { queue.first { $0.status == .ready } }
}
