import Foundation

// The JSON contract of the Android app's `KaraServer.kt` (Android SPEC §4.7): the same names, nil
// fields left out (`explicitNulls = false`), every other field always present (`encodeDefaults`).

struct AddRequest: Decodable {
    let url: String
    var singer: String?
    var key: Int?
    // From a search result: when title is given the entry skips the metadata lookup.
    var title: String?
    var channel: String?
    var thumb: String?
    var durationSec: Int64?
}

struct UpdateRequest: Decodable {
    var singer: String?
    var key: Int?
}

struct MoveRequest: Decodable {
    let index: Int
}

struct SearchResponse: Encodable {
    let results: [SearchResult]
}

struct UpNextDTO: Encodable {
    let entryId: String
    let secondsLeft: Int
}

struct StateResponse: Encodable {
    let version: Int64
    /// idle | upnext | playing
    let phase: String
    var upNext: UpNextDTO?
    var nowPlaying: QueueEntry?
    var player: PlayerSnapshot?
    let queue: [QueueEntry]
}

struct ErrorResponse: Encodable {
    let error: String
}
