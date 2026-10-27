import Synchronization
import Testing
@testable import KaraPitchTV

/// Ported from the Android app's `QueueRepositoryTest.kt`.
struct QueueStoreTests {
    /// Deterministic ids: e0, e1, …
    private final class IDs: Sendable {
        private let next = Atomic(0)
        func make() -> String { "e\(next.add(1, ordering: .relaxed).oldValue)" }
    }

    /// A lookup that waits until the test opens it, like a `CompletableDeferred`.
    private actor Gate {
        private var meta: VideoMeta?
        private var waiting: [CheckedContinuation<VideoMeta, Never>] = []

        func wait() async -> VideoMeta {
            if let meta { return meta }
            return await withCheckedContinuation { waiting.append($0) }
        }

        func open(_ meta: VideoMeta) {
            self.meta = meta
            waiting.forEach { $0.resume(returning: meta) }
            waiting = []
        }
    }

    private struct Blocked: Error, CustomStringConvertible {
        var description: String { "blocked" }
    }

    /// A store whose check calls `resolve`, except that a search result's details are kept.
    private func store(
        _ resolve: @escaping @Sendable (String) async throws -> VideoMeta = { VideoMeta(title: "Title \($0)", uploader: "up", thumb: nil, durationSec: 200) },
        findMusicVideo: (@Sendable (QueueEntry) async -> MusicVideo?)? = nil
    ) -> QueueStore {
        let ids = IDs()
        return QueueStore(
            check: { url, given in
                let found = try await resolve(url)
                return given ?? found
            },
            findMusicVideo: findMusicVideo,
            newID: ids.make
        )
    }

    private func ids(_ store: QueueStore) async -> [String] { await store.state.queue.map(\.id) }

    @Test func addResolvesInBackground() async throws {
        let gate = Gate()
        let s = store { _ in await gate.wait() }
        let e = try await s.add(url: "u1", singer: " Alex ", key: 9)
        #expect(await s.state.queue.first?.status == .resolving)
        #expect(e.singer == "Alex")
        #expect(e.presetKey == 6)
        await gate.open(VideoMeta(title: "Title u1", uploader: nil, thumb: nil, durationSec: 1))
        await s.settle()
        let resolved = try #require(await s.state.queue.first)
        #expect(resolved.status == .ready)
        #expect(resolved.title == "Title u1")
    }

    @Test func singerIsCappedAt40Characters() async throws {
        let e = try await store().add(url: "u1", singer: String(repeating: "x", count: 50), key: nil)
        #expect(e.singer.count == 40)
    }

    @Test func addWithMetaShowsItAtOnceAndIsStillChecked() async throws {
        let lookups = Atomic(0)
        let gate = Gate()
        let s = store { _ in
            lookups.add(1, ordering: .relaxed)
            return await gate.wait()
        }
        let e = try await s.add(url: "u1", singer: "Kim", key: -2, meta: VideoMeta(title: "Found", uploader: "chan", thumb: "thumb", durationSec: 180))
        #expect(e.status == .resolving)
        #expect(e.title == "Found")
        #expect(e.durationSec == 180)
        await gate.open(VideoMeta(title: "x", uploader: nil, thumb: nil, durationSec: 1))
        await s.settle()
        #expect(await s.state.queue.first?.status == .ready)
        #expect(await s.state.queue.first?.title == "Found")
        #expect(lookups.load(ordering: .relaxed) == 1)
    }

    @Test func aSearchResultThatCantPlayKeepsItsTitleAndIsAnnounced() async throws {
        let s = store { _ in throw Blocked() }
        try await s.add(url: "u1", singer: nil, key: nil, meta: VideoMeta(title: "Found", uploader: nil, thumb: nil, durationSec: 1))
        await s.settle()
        let e = try #require(await s.state.queue.first)
        #expect(e.status == .error)
        #expect(e.title == "Found")
        #expect(e.error == "blocked")
        #expect(e.musicVideoStatus == nil)
        for await failed in s.failed {
            #expect(failed.id == e.id)
            break
        }
    }

    @Test func findsTheMusicVideoOnceReady() async throws {
        let video = MusicVideo(url: "https://www.youtube.com/watch?v=mv", title: "Official Video", channel: "Band")
        let gate = Gate()
        let s = store(findMusicVideo: { entry in
            _ = await gate.wait()
            return entry.url == "u1" ? video : nil
        })
        try await s.add(url: "u1", singer: nil, key: nil)
        try await s.add(url: "u2", singer: nil, key: nil)
        while await s.state.queue.contains(where: { $0.musicVideoStatus != .searching }) { await Task.yield() }
        #expect(await s.state.queue.allSatisfy { $0.status == .ready })

        // The first song starts before its lookup finishes; the answer still reaches it.
        _ = await s.startNext()
        await gate.open(VideoMeta(title: "", uploader: nil, thumb: nil, durationSec: 0))
        await s.settle()
        #expect(await s.state.nowPlaying?.musicVideoStatus == .found)
        #expect(await s.state.nowPlaying?.musicVideo == video)
        #expect(await s.state.queue.first?.musicVideoStatus == MusicVideoStatus.none)
        #expect(await s.state.queue.first?.musicVideo == nil)
    }

    @Test func announcesEntriesOnceReady() async throws {
        let gate = Gate()
        let s = store { url in
            if url == "bad" { throw Blocked() }
            return await gate.wait()
        }
        try await s.add(url: "u1", singer: nil, key: nil)
        try await s.add(url: "u2", singer: nil, key: nil, meta: VideoMeta(title: "From search", uploader: nil, thumb: nil, durationSec: 1))
        try await s.add(url: "bad", singer: nil, key: nil)
        await gate.open(VideoMeta(title: "Title u1", uploader: nil, thumb: nil, durationSec: 1))
        await s.settle()

        var seen: [String] = []
        for await entry in s.added {
            seen.append(entry.title)
            if seen.count == 2 { break }
        }
        #expect(Set(seen) == ["From search", "Title u1"])
    }

    @Test func resolveFailureMarksError() async throws {
        let s = store { _ in throw Blocked() }
        try await s.add(url: "u1", singer: nil, key: nil)
        await s.settle()
        let e = try #require(await s.state.queue.first)
        #expect(e.status == .error)
        #expect(e.error == "blocked")
        #expect(await s.state.firstReady() == nil)
    }

    @Test func everyChangeBumpsVersion() async throws {
        let gate = Gate()
        let s = store { _ in await gate.wait() }
        let v0 = await s.state.version
        try await s.add(url: "u1", singer: nil, key: nil)
        let v1 = await s.state.version
        await gate.open(VideoMeta(title: "T", uploader: nil, thumb: nil, durationSec: 1))
        await s.settle()
        let v2 = await s.state.version
        await s.update(id: "e0", singer: "Sam", key: nil)
        let v3 = await s.state.version
        #expect(v0 < v1 && v1 < v2 && v2 < v3)
        #expect(await s.remove(id: "missing") == false)
        #expect(await s.state.version == v3)
    }

    @Test func moveClampsToBounds() async throws {
        let s = store()
        for i in 0..<3 { try await s.add(url: "u\(i)", singer: nil, key: nil) }
        #expect(await s.move(id: "e2", to: 0))
        #expect(await ids(s) == ["e2", "e0", "e1"])
        #expect(await s.move(id: "e2", to: 99))
        #expect(await ids(s) == ["e0", "e1", "e2"])
        #expect(await s.move(id: "e1", to: -5))
        #expect(await ids(s) == ["e1", "e0", "e2"])
        #expect(await s.move(id: "nope", to: 0) == false)
    }

    @Test func startNextSkipsUnresolvedAndRequeues() async throws {
        let slow = Gate()
        let s = store { url in
            url == "slow" ? await slow.wait() : VideoMeta(title: url, uploader: nil, thumb: nil, durationSec: 1)
        }
        try await s.add(url: "slow", singer: nil, key: nil)
        try await s.add(url: "fast", singer: nil, key: nil)
        while await s.state.firstReady() == nil { await Task.yield() }

        let first = try #require(await s.startNext())
        #expect(first.id == "e1")
        #expect(await s.state.nowPlaying?.id == "e1")
        #expect(await ids(s) == ["e0"])

        await s.requeueNowPlaying()
        #expect(await s.state.nowPlaying == nil)
        #expect(await ids(s) == ["e1", "e0"])

        _ = await s.startNext()
        await s.finishNowPlaying()
        #expect(await s.state.nowPlaying == nil)
        #expect(await ids(s) == ["e0"])
        #expect(await s.startNext() == nil)  // e0 is still resolving
        await slow.open(VideoMeta(title: "Slow", uploader: nil, thumb: nil, durationSec: 1))
        await s.settle()
    }

    @Test func removedWhileResolvingStaysRemoved() async throws {
        let gate = Gate()
        let s = store { _ in await gate.wait() }
        try await s.add(url: "u", singer: nil, key: nil)
        await s.remove(id: "e0")
        await gate.open(VideoMeta(title: "T", uploader: nil, thumb: nil, durationSec: 1))
        await s.settle()
        #expect(await s.state.queue.isEmpty)
    }

    @Test func fullQueueRejectsAdds() async throws {
        let s = store()
        for i in 0..<QueueStore.maxQueue {
            try await s.add(url: "u\(i)", singer: nil, key: nil, meta: VideoMeta(title: "t", uploader: nil, thumb: nil, durationSec: 1))
        }
        await #expect(throws: QueueError.full) { try await s.add(url: "one more", singer: nil, key: nil) }
    }

    @Test func updatesStreamsCurrentStateThenChanges() async throws {
        let gate = Gate()
        let s = store { _ in await gate.wait() }
        let updates = await s.updates()
        try await s.add(url: "u1", singer: nil, key: nil, meta: VideoMeta(title: "t", uploader: nil, thumb: nil, durationSec: 1))
        var versions: [Int64] = []
        for await state in updates {
            versions.append(state.version)
            if state.queue.count == 1 { break }
        }
        #expect(versions.last == 1)
        await gate.open(VideoMeta(title: "t", uploader: nil, thumb: nil, durationSec: 1))
        await s.settle()
    }
}
