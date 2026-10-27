import Foundation

/// A music genre the TV search can be narrowed to. Its `term` is added to the YouTube query.
struct Genre: Identifiable, Hashable, Sendable {
    let name: String
    /// Words added to the query; tuned for what finds karaoke versions of that genre.
    let term: String
    let emoji: String
    /// Tile color, as a hue from 0 to 1.
    let hue: Double

    var id: String { name }

    static let all: [Genre] = [
        Genre(name: "Pop", term: "pop", emoji: "🎤", hue: 0.92),
        Genre(name: "Rock", term: "rock", emoji: "🎸", hue: 0.0),
        Genre(name: "Country", term: "country", emoji: "🤠", hue: 0.08),
        Genre(name: "R&B", term: "r&b soul", emoji: "🎷", hue: 0.75),
        Genre(name: "Hip-Hop", term: "hip hop rap", emoji: "🎧", hue: 0.6),
        Genre(name: "Ballads", term: "ballad love song", emoji: "💖", hue: 0.97),
        Genre(name: "Disney", term: "disney", emoji: "🏰", hue: 0.55),
        Genre(name: "Broadway", term: "broadway musical", emoji: "🎭", hue: 0.82),
        Genre(name: "Latin", term: "latin", emoji: "💃", hue: 0.04),
        Genre(name: "K-Pop", term: "k-pop", emoji: "🌟", hue: 0.88),
        Genre(name: "Jazz", term: "jazz standards", emoji: "🎺", hue: 0.12),
        Genre(name: "Reggae", term: "reggae", emoji: "🌴", hue: 0.3),
    ]
}

extension SearchService {
    /// The typed words plus the genre's term, skipping the term when it's already typed.
    /// With nothing typed, the genre alone is the search.
    static func withGenre(_ query: String, _ genre: Genre?) -> String {
        let q = query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let genre, q.range(of: genre.term, options: .caseInsensitive) == nil else { return q }
        return q.isEmpty ? genre.term : "\(q) \(genre.term)"
    }
}
