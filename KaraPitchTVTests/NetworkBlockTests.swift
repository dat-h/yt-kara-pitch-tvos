import Foundation
import SmartTubeIOSCore
import Synchronization
import Testing
@testable import KaraPitchTV

struct NetworkBlockTests {
    /// A clock the test moves by hand.
    private final class Clock: Sendable {
        private let instant = Mutex(ContinuousClock.now)
        var now: ContinuousClock.Instant { instant.withLock { $0 } }
        func advance(_ by: Duration) { instant.withLock { $0 += by } }
    }

    @Test func twoVideosRefusedMeansBlocked() async {
        let block = NetworkBlock()
        await block.refusedSignIn("a")
        #expect(await !block.isBlocked)  // could just be age-restricted
        await block.refusedSignIn("a")
        #expect(await !block.isBlocked)  // the same video again proves nothing
        await block.refusedSignIn("b")
        #expect(await block.isBlocked)
    }

    @Test func aSuccessClearsIt() async {
        let block = NetworkBlock()
        await block.refusedSignIn("a")
        await block.succeeded()
        await block.refusedSignIn("b")
        #expect(await !block.isBlocked)
    }

    @Test func itWearsOffAfterTheCooldown() async {
        let clock = Clock()
        let block = NetworkBlock(now: { clock.now })
        await block.blocked()
        clock.advance(NetworkBlock.cooldown - .seconds(1))
        #expect(await block.isBlocked)
        clock.advance(.seconds(2))
        #expect(await !block.isBlocked)
        // Counting starts over: one refusal after the cooldown isn't a block yet.
        await block.refusedSignIn("c")
        #expect(await !block.isBlocked)
    }
}

/// `StreamResolver` against fake InnerTube answers.
struct StreamResolverBlockTests {
    /// How many times the fake InnerTube was asked.
    private final class Calls: Sendable {
        private let count = Atomic(0)
        var value: Int { count.load(ordering: .relaxed) }
        func add() { count.add(1, ordering: .relaxed) }
    }

    private static let playable = [
        VideoFormat(label: "1080p", width: 1920, height: 1080, fps: 30, mimeType: #"video/mp4; codecs="avc1.640028""#,
                    url: URL(string: "https://rr1.googlevideo.com/videoplayback?itag=137"), bitrate: 4_000_000),
        VideoFormat(label: "audio", width: 0, height: 0, fps: 0, mimeType: #"audio/mp4; codecs="mp4a.40.2""#,
                    url: URL(string: "https://rr1.googlevideo.com/videoplayback?itag=140"), bitrate: 130_000),
    ]

    /// A resolver whose clients refuse every video in `refused` for sign-in, and counts the calls.
    private func resolver(refusing refused: Set<String>, error: any Error = APIError.signInRequired, calls: Calls) -> StreamResolver {
        var resolver = StreamResolver(api: InnerTubeAPI())
        resolver.fetch = { _, videoID in
            calls.add()
            if refused.contains(videoID) { throw error }
            return ClientAnswer(formats: Self.playable, meta: VideoMeta(title: videoID, uploader: nil, thumb: nil, durationSec: 200))
        }
        return resolver
    }

    private func failure(_ resolver: StreamResolver, _ videoID: String) async -> StreamResolverError? {
        do {
            _ = try await resolver.resolve(videoID: videoID)
            return nil
        } catch {
            return error as? StreamResolverError
        }
    }

    @Test func oneRefusalSaysItMayBeAgeRestricted() async {
        let calls = Calls()
        let r = resolver(refusing: ["a"], calls: calls)
        let error = await failure(r, "a")
        #expect(error?.reason == "YouTube wants a sign-in for this video (it may be age-restricted). Pick another video")
        #expect(calls.value == StreamClient.resolveOrder.count)  // every client tried
    }

    @Test func aSecondVideoRefusedSaysTheNetworkIsLimitedAndStopsAsking() async {
        let calls = Calls()
        let r = resolver(refusing: ["a", "b", "c"], calls: calls)
        _ = await failure(r, "a")
        let second = await failure(r, "b")
        #expect(second?.reason == "YouTube is limiting this network for a while. Try again in a few minutes")

        // While blocked, one client is enough to know.
        let before = calls.value
        guard case .networkBlocked = await failure(r, "c") else {
            Issue.record("expected networkBlocked")
            return
        }
        #expect(calls.value - before == 1)
    }

    @Test func aPlayableVideoLiftsTheBlock() async throws {
        let calls = Calls()
        let r = resolver(refusing: ["a", "b"], calls: calls)
        _ = await failure(r, "a")
        _ = await failure(r, "b")
        #expect(await r.block.isBlocked)
        _ = try await r.resolve(videoID: "ok")
        #expect(await !r.block.isBlocked)
    }

    @Test func anExplicitIPBlockStopsAtOnce() async {
        let calls = Calls()
        let r = resolver(refusing: ["a"], error: APIError.ipBlocked("Sign in to confirm you're not a bot"), calls: calls)
        guard case .networkBlocked = await failure(r, "a") else {
            Issue.record("expected networkBlocked")
            return
        }
        #expect(calls.value == 1)
    }
}
