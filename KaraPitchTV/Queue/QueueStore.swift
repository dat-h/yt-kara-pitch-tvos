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

    /// Each entry once its check finds it playable (READY).
    nonisolated let added: AsyncStream<QueueEntry>
    private let addedContinuation: AsyncStream<QueueEntry>.Continuation
    /// Each entry whose check finds it can't be played (ERROR).
    nonisolated let failed: AsyncStream<QueueEntry>
    private let failedContinuation: AsyncStream<QueueEntry>.Continuation

    private let check: @Sendable (_ url: String, _ given: VideoMeta?) async throws -> VideoMeta
    private let findMusicVideo: (@Sendable (QueueEntry) async -> MusicVideo?)?
    private let newID: @Sendable () -> String
    private var watchers: [UUID: AsyncStream<QueueState>.Continuation] = [:]
    private var resolving: [String: Task<Void, Never>] = [:]

    /// `check` finds out whether `url` can be played and returns its details (`given` is what a
    /// search result already knows). `findMusicVideo` looks for the song's music video once it's READY.
    init(
        check: @escaping @Sendable (_ url: String, _ given: VideoMeta?) async throws -> VideoMeta,
        findMusicVideo: (@Sendable (QueueEntry) async -> MusicVideo?)? = nil,
        newID: @escaping @Sendable () -> String = { String(UUID().uuidString.prefix(8)).lowercased() }
    ) {
        self.check = check
        self.findMusicVideo = findMusicVideo
        self.newID = newID
        (added, addedContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
        (failed, failedContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(16))
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

    /// Adds `url` (already normalized) and checks in the background that it can be played. A search
    /// result's `meta` shows at once; a pasted link shows "Loading…" until the check fills it in.
    @discardableResult
    func add(url: String, singer: String?, key: Int?, meta: VideoMeta? = nil) throws -> QueueEntry {
        guard state.queue.count < Self.maxQueue else { throw QueueError.full }
        var entry = QueueEntry(id: newID(), url: url, singer: Self.clean(singer), presetKey: Key.clamp(key ?? 0))
        if let meta { entry.show(meta) }
        commit { $0.queue.append(entry) }
        resolving[entry.id] = Task { [entry] in await resolve(entry.id, url: url, given: meta) }
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

    private func resolve(_ id: String, url: String, given: VideoMeta?) async {
        let meta: Result<VideoMeta, any Error>
        do {
            meta = .success(try await check(url, given))
        } catch {
            meta = .failure(error)
        }
        resolving[id] = nil
        // Removed while resolving: it stays removed.
        guard let index = state.queue.firstIndex(where: { $0.id == id }) else { return }
        var entry = state.queue[index].resolved(with: meta)
        guard entry.status == .ready else {
            commit { $0.queue[index] = entry }
            failedContinuation.yield(entry)
            return
        }
        if let findMusicVideo {
            entry.musicVideoStatus = .searching
            resolving["\(id)/music"] = Task { [entry] in
                let found = await findMusicVideo(entry)
                self.attach(found, to: id)
            }
        }
        commit { $0.queue[index] = entry }
        addedContinuation.yield(entry)
    }

    /// Records the music video lookup's answer, wherever the entry is by now.
    private func attach(_ video: MusicVideo?, to id: String) {
        resolving["\(id)/music"] = nil
        func apply(_ entry: inout QueueEntry) {
            entry.musicVideo = video
            entry.musicVideoStatus = video == nil ? MusicVideoStatus.none : .found
        }
        if let index = state.queue.firstIndex(where: { $0.id == id }) {
            commit { apply(&$0.queue[index]) }
        } else if state.nowPlaying?.id == id {
            commit { apply(&$0.nowPlaying!) }
        }
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
    mutating func show(_ meta: VideoMeta) {
        title = meta.title
        uploader = meta.uploader
        thumb = meta.thumb
        durationSec = meta.durationSec
    }

    func resolved(with meta: Result<VideoMeta, any Error>) -> QueueEntry {
        var entry = self
        switch meta {
        case let .success(m):
            entry.show(m)
            entry.status = .ready
        case let .failure(error):
            // A search result keeps its title; a pasted link has none yet.
            if entry.title == QueueEntry.loadingTitle { entry.title = QueueEntry.failedTitle }
            entry.status = .error
            entry.error = String(describing: error)
        }
        return entry
    }
}
