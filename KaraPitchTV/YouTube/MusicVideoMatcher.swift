import Foundation

/// A search result that might be a song's music video.
struct MusicVideoCandidate: Equatable, Sendable {
    let id: String
    let title: String
    var channel = ""
    var durationSec: Int64 = 0
    var isLive = false
    var isShort = false
}

/// The rules for finding a karaoke song's own music video: what to search for, what to throw out,
/// and how to rank what's left.
enum MusicVideoMatcher {
    /// How many of the best candidates are tried before giving up.
    static let maxTried = 3
    /// Longer than this is a compilation or a long-form edit, not the song.
    static let maxDurationSec: Int64 = 15 * 60
    /// A music video's length within this ratio of the karaoke version's.
    static let durationRatio = 0.6...1.6
    /// The share of each part's words (the artist's, the song's) a candidate must contain, in its
    /// title or channel.
    static let minShare = 0.75

    /// Karaoke wording, dropped from the song's name. Longer phrases first.
    private static let karaokeWords = [
        "karaoke version", "karaoke songs", "karaoke", "instrumental version", "instrumental", "with lyrics",
        "lyric video", "lyrics", "lyric", "sing along", "singalong", "backing track", "no vocals", "without vocals",
        "lower key", "higher key", "original key", "male key", "female key", "key of", "hd", "4k", "version",
    ]
    /// Karaoke channels that often put their name in the title.
    private static let karaokeChannels = [
        "sing king", "singking", "karafun", "musisi", "zoom", "stingray", "sunfly", "party tyme", "lucky voice", "karaoke channel",
    ]
    /// Phrases that introduce the artist inside brackets, e.g. "(Originally Performed by ABBA)".
    private static let artistIntros = ["originally performed by", "performed by", "in the style of", "made famous by", "as made famous by"]
    /// Words in a candidate's title that mean it isn't the music video.
    private static let rejectWords = [
        "karaoke", "instrumental", "lyric", "lyrics", "cover", "live", "reaction", "remix", "tutorial", "lesson",
        "piano", "guitar", "drum", "drums", "8d", "sped up", "slowed", "nightcore", "behind the scenes", "making of",
        "teaser", "trailer", "acapella", "a cappella", "official audio", "visualizer", "visualiser", "shorts", "concert",
        "performance",
    ]
    private static let stopwords: Set<String> = ["the", "a", "an", "of", "and", "feat", "ft", "by", "with", "x", "vs"]

    /// The artist and song words of a karaoke video's title.
    /// "ABBA - Dancing Queen (Karaoke Version)" → "ABBA Dancing Queen".
    static func songQuery(fromKaraokeTitle title: String) -> String {
        songParts(fromKaraokeTitle: title).joined(separator: " ")
    }

    /// The title's parts that still say something once karaoke wording is gone: usually the artist
    /// and the song, in either order. "Dancing Queen - ABBA | Karaoke Version | KaraFun" →
    /// ["Dancing Queen", "ABBA"].
    static func songParts(fromKaraokeTitle title: String) -> [String] {
        // Bracketed asides are karaoke notes, except one naming the original artist.
        let text = title.replacing(/[(\[{]([^)\]}]*)[)\]}]/) { match in
            let inside = String(match.output.1)
            let lower = inside.lowercased()
            guard let intro = artistIntros.first(where: { lower.contains($0) }), let range = lower.range(of: intro) else { return " " }
            let artist = inside[inside.index(inside.startIndex, offsetBy: lower.distance(from: lower.startIndex, to: range.upperBound))...]
            return " - \(artist) "
        }
        return text.split(separator: /\s+[-–—]\s+|[|•]|:\s/).map { strip(String($0)) }.filter { !$0.isEmpty }
    }

    static func searchQuery(fromKaraokeTitle title: String) -> String {
        "\(songQuery(fromKaraokeTitle: title)) official music video"
    }

    /// The candidates worth trying, best first, at most `maxTried`.
    static func rank(_ candidates: [MusicVideoCandidate], karaokeTitle: String, karaokeID: String, karaokeDurationSec: Int64) -> [MusicVideoCandidate] {
        let parts = songParts(fromKaraokeTitle: karaokeTitle).map { Set(significant(words($0))) }.filter { !$0.isEmpty }
        let song = songQuery(fromKaraokeTitle: karaokeTitle)
        let query = Set(significant(words(song)))
        guard !query.isEmpty else { return [] }
        // A word the song's own name has (a "Remix", say) doesn't count against a candidate.
        let songText = phraseText(song)
        let allowed = rejectWords.filter { songText.contains(" \($0) ") }

        let scored = candidates.enumerated().compactMap { rank, candidate -> (MusicVideoCandidate, Double)? in
            let title = phraseText(candidate.title)
            let channel = phraseText(candidate.channel)
            guard candidate.id != karaokeID, !candidate.isLive, !candidate.isShort,
                !channel.hasSuffix(" topic "),
                !rejectWords.contains(where: { !allowed.contains($0) && title.contains(" \($0) ") })
            else { return nil }

            var closeness = 0.5
            if karaokeDurationSec > 0 {
                guard candidate.durationSec > 0, candidate.durationSec <= maxDurationSec else { return nil }
                let ratio = Double(candidate.durationSec) / Double(karaokeDurationSec)
                guard durationRatio.contains(ratio) else { return nil }
                closeness = 1 - min(1, abs(ratio - 1) / 0.6)
            }

            let titleWords = Set(words(candidate.title))
            let channelWords = Set(words(candidate.channel))
            // Each part (the artist, the song) on its own, so the artist's other songs don't pass.
            let found = titleWords.union(channelWords)
            guard parts.allSatisfy({ Double($0.intersection(found).count) / Double($0.count) >= minShare }) else { return nil }

            var score = 2 * Double(query.intersection(titleWords).count) / Double(query.count) + closeness - 0.1 * Double(rank)
            if title.contains(" official music video ") || title.contains(" official video ") { score += 3 }
            if title.contains(" music video ") { score += 1 }
            if channel.hasSuffix("vevo ") || channel.contains(" official ") { score += 2 }
            let artist = significant(artistWords(candidate.channel))
            if !artist.isEmpty && Set(artist).isSubset(of: query) { score += 2 }
            return (candidate, score)
        }
        return Array(scored.sorted { $0.1 > $1.1 }.prefix(maxTried).map(\.0))
    }

    // MARK: - Text

    /// Removes karaoke wording and channel names from one part of a title, and its separators.
    private static func strip(_ part: String) -> String {
        var text = " " + words(part, keepCase: true).joined(separator: " ") + " "
        for phrase in karaokeWords + karaokeChannels {
            while let range = text.range(of: " \(phrase) ", options: [.caseInsensitive, .diacriticInsensitive]) {
                text.replaceSubrange(range, with: " ")
            }
        }
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// Lowercased, accent-free words: "Beyoncé - Halo!" → ["beyonce", "halo"].
    static func words(_ text: String, keepCase: Bool = false) -> [String] {
        let folded = keepCase ? text : text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return folded
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "’", with: "")
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    private static func significant(_ words: [String]) -> [String] {
        words.filter { !stopwords.contains($0) }
    }

    /// Words padded with spaces, so phrases match whole words: " official music video ".
    private static func phraseText(_ text: String) -> String {
        " " + words(text).joined(separator: " ") + " "
    }

    /// A channel's name without the label words: "ABBAVEVO" → ["abba"], "Rick Astley" → ["rick", "astley"].
    private static func artistWords(_ channel: String) -> [String] {
        words(channel).compactMap { word -> String? in
            let trimmed = word.hasSuffix("vevo") ? String(word.dropLast(4)) : word
            return ["official", "music", "records", "tv", "vevo", ""].contains(trimmed) ? nil : trimmed
        }
    }
}
