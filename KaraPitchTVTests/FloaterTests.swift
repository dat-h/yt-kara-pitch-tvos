import Testing
@testable import KaraPitchTV

struct FloaterTests {
    /// SplitMix64, so the placement checks don't depend on luck.
    private struct SeededRNG: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    @Test func burstUsesTheReactionsEmojis() {
        var rng = SeededRNG(state: 1)
        for reaction in Reaction.allCases {
            let burst = Floater.burst(for: reaction, using: &rng)
            #expect(burst.count == Floater.perPress)
            #expect(burst.allSatisfy { Floater.emojis(for: reaction).contains($0.emoji) })
        }
    }

    @Test func mostlyOnTheSidesAndNeverOverTheLyrics() {
        var rng = SeededRNG(state: 42)
        let floaters = (0..<400).flatMap { _ in Floater.burst(for: .laugh, using: &rng) }
        let onSides = floaters.filter { $0.x <= Floater.sideBand || $0.x >= 1 - Floater.sideBand }
        #expect(Double(onSides.count) / Double(floaters.count) > 0.8)
        // The rest stay near the top, above where lyrics usually run.
        #expect(floaters.filter { $0.x > Floater.sideBand && $0.x < 1 - Floater.sideBand }.allSatisfy { $0.y < 0.33 })
        #expect(floaters.allSatisfy { (0...1).contains($0.x) && (0...1).contains($0.y) })
    }
}
