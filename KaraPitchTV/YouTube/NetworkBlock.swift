import Foundation

/// Whether YouTube seems to be refusing this network ("Sign in to confirm you're not a bot").
///
/// SmartTubeIOSCore reports that and a real age restriction as the same `signInRequired`, so one
/// refusal can't tell them apart. A block refuses every video, though: two different videos refused
/// with no success in between count as a block, for `cooldown` or until something resolves.
actor NetworkBlock {
    static let cooldown: Duration = .seconds(10 * 60)

    private let now: @Sendable () -> ContinuousClock.Instant
    /// Videos refused for sign-in since the last success.
    private var refused: Set<String> = []
    private var blockedAt: ContinuousClock.Instant?

    init(now: @escaping @Sendable () -> ContinuousClock.Instant = { .now }) {
        self.now = now
    }

    var isBlocked: Bool {
        guard let blockedAt else { return false }
        return now() - blockedAt < Self.cooldown
    }

    /// Every client refused `videoID` for sign-in.
    func refusedSignIn(_ videoID: String) {
        if blockedAt != nil && !isBlocked {
            // The cooldown ran out: start counting again.
            blockedAt = nil
            refused = []
        }
        refused.insert(videoID)
        if refused.count >= 2 { blockedAt = now() }
    }

    /// YouTube said outright that the network is blocked.
    func blocked() {
        blockedAt = now()
    }

    func succeeded() {
        refused = []
        blockedAt = nil
    }
}
