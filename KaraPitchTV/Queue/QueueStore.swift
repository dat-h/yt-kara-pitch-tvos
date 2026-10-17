import Foundation

enum QueueError: Error, Equatable, CustomStringConvertible {
    case full

    var description: String {
        switch self {
        case .full: "The queue is full"
        }
    }
}

/// The in-memory queue, a port of the Android app's `QueueRepository.kt`. The web server mutates
/// it while the TV session reads and advances it.
actor QueueStore {
    static let maxQueue = 200
    static let maxSinger = 40

    private(set) var state = QueueState()

    /// Each entry once it is READY: at once for search results, after the lookup for pasted links.
    nonisolated let added: AsyncStream<QueueEntry>
    private let addedContinuation: AsyncStream<QueueEntry>.Continuation

    private let resolveMeta: @Sendable (String) async throws -> VideoMeta
    private let newID: @Sendable () -> String
    private var watchers: [UUID: AsyncStream<QueueState>.Continuation] = [:]
    private var resolving: [String: Task<Void, Never>] = [:]

    init(
        resolveMeta: @escaping @Sendable (_ url: String) async throws -> VideoMeta,
        newID: @escaping @Sendable () -> String = { String(UUID().uuidString.prefix(8)).lowercased() }
    ) {
        self.resolveMeta = resolveMeta
        self.newID = newID
        (added, addedContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
    }

    /// The current state, then every change.
    func updates() -> AsyncStream<QueueState> {
        let (stream, continuation) = AsyncStream.makeStream(of: QueueState.self, bufferingPolicy: .bufferingNewest(1))
        let id = UUID()
        watchers[id] = continuation
        continuation.yield(state)
        continuation.onTermination = { _ in Task { await self.removeWatcher(id) } }
        return stream
    }

    /// Adds `url` (already normalized). Without `meta` its title, thumbnail and length are resolved
    /// in the background; with it (a search result already carries them) the entry is READY at once.
    @discardableResult
    func add(url: String, singer: String?, key: Int?, meta: VideoMeta? = nil) throws -> QueueEntry {
        guard state.queue.count < Self.maxQueue else { throw QueueError.full }
        let base = QueueEntry(id: newID(), url: url, singer: Self.clean(singer), presetKey: Key.clamp(key ?? 0))
        let entry = meta.map { base.resolved(with: .success($0)) } ?? base
        commit { $0.queue.append(entry) }
        if meta != nil {
            addedContinuation.yield(entry)
        } else {
            resolving[entry.id] = Task { await resolve(entry.id, url: url) }
        }
        return entry
    }

    @discardableResult
    func remove(id: String) -> Bool {
        guard let index = state.queue.firstIndex(where: { $0.id == id }) else { return false }
        commit { $0.queue.remove(at: index) }
        return true
    }

    /// Moves `id` to `index`, clamped to the queue's bounds.
    @discardableResult
    func move(id: String, to index: Int) -> Bool {
        guard let from = state.queue.firstIndex(where: { $0.id == id }) else { return false }
        commit { s in
            let entry = s.queue.remove(at: from)
            s.queue.insert(entry, at: min(max(index, 0), s.queue.count))
        }
        return true
    }

    @discardableResult
    func update(id: String, singer: String?, key: Int?) -> QueueEntry? {
        guard let index = state.queue.firstIndex(where: { $0.id == id }) else { return nil }
        var entry = state.queue[index]
        if let singer { entry.singer = Self.clean(singer) }
        if let key { entry.presetKey = Key.clamp(key) }
        commit { $0.queue[index] = entry }
        return entry
    }

    /// Takes the first READY entry off the queue and makes it the song now playing.
    func startNext() -> QueueEntry? {
        guard let next = state.firstReady() else { return nil }
        commit { s in
            s.nowPlaying = next
            s.queue.removeAll { $0.id == next.id }
        }
        return next
    }

    /// The song now playing is over (finished, skipped or failed).
    func finishNowPlaying() {
        guard state.nowPlaying != nil else { return }
        commit { $0.nowPlaying = nil }
    }

    /// The song was interrupted (the app left the screen): put it back at the front.
    func requeueNowPlaying() {
        guard let nowPlaying = state.nowPlaying else { return }
        commit { s in
            s.nowPlaying = nil
            s.queue.insert(nowPlaying, at: 0)
        }
    }

    /// Waits for every background lookup started so far, and any they lead to. For tests.
    func settle() async {
        while let task = resolving.values.first {
            await task.value
        }
    }

    private func resolve(_ id: String, url: String) async {
        let meta: Result<VideoMeta, any Error>
        do {
            meta = .success(try await resolveMeta(url))
        } catch {
            meta = .failure(error)
        }
        resolving[id] = nil
        // Removed while resolving: it stays removed.
        guard let index = state.queue.firstIndex(where: { $0.id == id }) else { return }
        let entry = state.queue[index].resolved(with: meta)
        commit { $0.queue[index] = entry }
        if entry.status == .ready { addedContinuation.yield(entry) }
    }

    private func commit(_ change: (inout QueueState) -> Void) {
        change(&state)
        state.version += 1
        for watcher in watchers.values { watcher.yield(state) }
    }

    private func removeWatcher(_ id: UUID) { watchers[id] = nil }

    private static func clean(_ singer: String?) -> String {
        String((singer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(maxSinger))
    }
}

private extension QueueEntry {
    func resolved(with meta: Result<VideoMeta, any Error>) -> QueueEntry {
        var entry = self
        switch meta {
        case let .success(m):
            entry.title = m.title
            entry.uploader = m.uploader
            entry.thumb = m.thumb
            entry.durationSec = m.durationSec
            entry.status = .ready
        case let .failure(error):
            entry.title = "Couldn't load this video"
            entry.status = .error
            entry.error = String(describing: error)
        }
        return entry
    }
}
