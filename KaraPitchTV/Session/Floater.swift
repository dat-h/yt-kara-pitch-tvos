import Foundation

/// One emoji drifting up the TV screen after a phone sends a reaction.
struct Floater: Identifiable, Equatable, Sendable {
    static let lifetime: Duration = .seconds(3)
    /// Emojis per press, so one press reads as a small burst.
    static let perPress = 3
    /// Share of floaters kept to the side bands, away from the lyrics in the middle.
    static let sideShare = 0.85
    /// Width of each side band, as a fraction of the screen.
    static let sideBand = 0.2

    let id: UUID
    let emoji: String
    /// Start position as a fraction of the screen (0…1 each way, from the top left).
    let x: Double
    let y: Double
    /// Seconds after the press before it shows, so a burst doesn't appear all at once.
    let delay: Double
    let size: Double

    static func emojis(for reaction: Reaction) -> [String] {
        switch reaction {
        case .clap: ["👏"]
        case .ovation: ["🙌", "🎉", "👏"]
        case .boo: ["👎", "🍅"]
        case .laugh: ["😂", "🤣"]
        }
    }

    /// A burst for one press: mostly in the side bands, now and then across the top, where
    /// karaoke lyrics rarely sit.
    static func burst(for reaction: Reaction, using rng: inout some RandomNumberGenerator) -> [Floater] {
        let emojis = emojis(for: reaction)
        return (0..<perPress).map { index in
            let x: Double
            let y: Double
            if Double.random(in: 0..<1, using: &rng) < sideShare {
                let left = Bool.random(using: &rng)
                let offset = Double.random(in: 0.04...sideBand, using: &rng)
                x = left ? offset : 1 - offset
                y = Double.random(in: 0.35...0.9, using: &rng)
            } else {
                x = Double.random(in: sideBand...(1 - sideBand), using: &rng)
                y = Double.random(in: 0.22...0.32, using: &rng)
            }
            return Floater(
                id: UUID(),
                emoji: emojis[index % emojis.count],
                x: x,
                y: y,
                delay: Double(index) * 0.18 + Double.random(in: 0...0.1, using: &rng),
                size: Double.random(in: 84...120, using: &rng)
            )
        }
    }
}
