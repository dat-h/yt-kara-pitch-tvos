import Foundation

enum EntryStatus: String, Codable, Sendable {
    case resolving = "RESOLVING"
    case ready = "READY"
    case error = "ERROR"
}

enum MusicVideoStatus: String, Codable, Sendable {
    case searching = "SEARCHING"
    case found = "FOUND"
    case none = "NONE"
}

/// The song's own music video, played behind the karaoke video. Only searched for when the song is
/// queued; it's resolved when the song is about to play, trying `fallbacks` if it won't.
struct MusicVideo: Codable, Equatable, Sendable {
    let url: String
    let title: String
    var channel: String?
    /// The runners-up's watch URLs, best first.
    var fallbacks: [String]?
}

struct QueueEntry: Codable, Equatable, Identifiable, Sendable {
    static let loadingTitle = "Loading…"
    /// A pasted link's title when its check fails.
    static let failedTitle = "Couldn't load this video"

    let id: String
    /// The canonical watch URL (see `YouTubeURL.normalize`).
    let url: String
    var title = QueueEntry.loadingTitle
    var uploader: String?
    var thumb: String?
    var durationSec: Int64 = 0
    var singer = ""
    /// Semitones, applied when the song starts.
    var presetKey = 0
    var status = EntryStatus.resolving
    var error: String?
    /// Nil until the entry is READY and the lookup starts.
    var musicVideoStatus: MusicVideoStatus?
    var musicVideo: MusicVideo?
}

extension QueueEntry {
    /// What plays behind the song, for the TV; nil before the lookup starts.
    var musicVideoLabel: String? {
        switch musicVideoStatus {
        case .searching: "Finding the music video…"
        case .found: musicVideo.map { "🎬 \($0.title)" }
        case .some(.none): "No music video"
        case nil: nil
        }
    }
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
