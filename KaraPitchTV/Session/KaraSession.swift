import Foundation
import Observation
import SmartTubeIOSCore
import os

enum Phase: Equatable, Sendable {
    case idle
    case upNext(QueueEntry, secondsLeft: Int)
    case playing(QueueEntry)
}

/// Runs the night: waits for a ready song, counts it in, plays it, and moves on. While the app
/// isn't active the session waits, and a song cut off that way goes back to the front of the queue.
/// A port of the Android `KaraSession.kt`.
@MainActor @Observable
final class KaraSession {
    static let countInSeconds = 5
    static let noticeDuration: Duration = .seconds(2)
    static let bannerDuration: Duration = .seconds(4)
    private static let retryCodes: Set<Int> = [403, 410]
    static let backConfirm: Duration = .seconds(3)
    /// Oldest emojis go first past this, so a flood of presses can't fill the screen.
    static let maxFloaters = 36

    let store: QueueStore
    let player = KaraPlayer()
    let reactions = ReactionPlayer()
    private(set) var phase = Phase.idle
    /// Mirrors `store.state` for the screens.
    private(set) var queue = QueueState()
    /// A short message for the TV screen, cleared after `noticeDuration`.
    private(set) var notice: String?
    /// The TV search screen is showing (over whatever is playing).
    var searchOpen = false
    /// The "added to queue" banner showing now. Songs queued in a burst each get their turn.
    private(set) var banner: QueueEntry?
    /// Every singer seen while the app is open, most recently used first. Names stay after their
    /// songs leave the queue, and go when the app quits.
    private(set) var singers: [String] = []
    /// Reaction emojis on screen now; each leaves after `Floater.lifetime`.
    private(set) var floaters: [Floater] = []

    @ObservationIgnored private let api: InnerTubeAPI
    @ObservationIgnored private let resolver: StreamResolver
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var startNowRequested = false
    @ObservationIgnored private var waiters: [CheckedContinuation<Void, Never>] = []
    @ObservationIgnored private var noticeID = 0
    @ObservationIgnored private var lastBackAt: ContinuousClock.Instant?
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(api: InnerTubeAPI = InnerTubeAPI()) {
        let resolver = StreamResolver(api: api)
        self.api = api
        self.resolver = resolver
        store = QueueStore { url in
            guard let id = YouTubeURL.videoID(of: url) else { throw StreamResolverError.noPlayableStream(videoID: url, attempts: []) }
            return try await resolver.meta(videoID: id)
        }
    }

    func start() {
        guard tasks.isEmpty else { return }
        tasks = [
            Task { [store] in
                for await state in await store.updates() {
                    self.queue = state
                    // Picks up names from phones, including renames, without reordering known ones.
                    for name in ([state.nowPlaying].compactMap { $0 } + state.queue).map(\.singer)
                    where !self.singers.contains(name) {
                        self.rememberSinger(name)
                    }
                    self.wake()
                }
            },
            Task { await loop() },
            Task { [store] in
                for await entry in store.added {
                    self.rememberSinger(entry.singer)
                    self.banner = entry
                    try? await Task.sleep(for: Self.bannerDuration)
                    self.banner = nil
                    try? await Task.sleep(for: .milliseconds(400))  // let it slide out before the next one
                }
            },
        ]
    }

    /// The HTTP API over this session's queue and state.
    func makeRouter() -> Router {
        Router(
            store: store,
            session: { await self.apiView() },
            search: { [api] query, addKaraoke in try await SearchService.search(query, addKaraoke: addKaraoke, api: api) },
            webFile: WebFiles.data,
            react: { reaction in await self.react(reaction) }
        )
    }

    private func apiView() -> SessionView { SessionView(phase: phase, player: player.snapshot) }

    /// Follows `scenePhase`: leaving the screen stops the song and requeues it.
    func setActive(_ active: Bool) {
        isActive = active
        if active { player.reattach() } else { player.release() }
        wake()
    }

    /// Select on the remote during the up-next countdown.
    func startNow() {
        startNowRequested = true
        wake()
    }

    func adjustKey(_ delta: Int) {
        player.adjustKey(delta)
        notify(Key.label(player.key))
    }

    func skip(notice: String) {
        notify(notice)
        player.skip()
    }

    /// A TV search that loads its results a batch at a time.
    func searchPager(_ query: String, addKaraoke: Bool) -> SearchPager {
        let q = SearchService.buildQuery(query, addKaraoke: addKaraoke)
        return SearchPager { [api] token in
            let group = try await api.search(query: q, continuationToken: token, filter: .default)
            return (SearchService.songs(from: group.videos), group.nextPageToken)
        }
    }

    /// Adds a search result picked on the TV; it's ready at once since the result carries its details.
    func addFromSearch(_ result: SearchResult, singer: String, key: Int) async {
        do {
            let meta = VideoMeta(title: result.title, uploader: result.channel, thumb: result.thumb, durationSec: result.durationSec)
            try await store.add(url: result.url, singer: singer, key: key, meta: meta)
        } catch {
            notify(String(describing: error))
        }
    }

    /// Back while a song plays: the first press warns, a second within `backConfirm` stops the song.
    func backPressed() {
        let now = ContinuousClock.now
        if let last = lastBackAt, now - last < Self.backConfirm {
            lastBackAt = nil
            skip(notice: "Stopped")
        } else {
            lastBackAt = now
            notify("Press Back again to stop this song")
        }
    }

    /// A phone's reaction: its sound, plus a burst of emojis that float up and leave.
    func react(_ reaction: Reaction) {
        reactions.play(reaction)
        var rng = SystemRandomNumberGenerator()
        let burst = Floater.burst(for: reaction, using: &rng)
        floaters = Array((floaters + burst).suffix(Self.maxFloaters))
        let ids = Set(burst.map(\.id))
        Task {
            try? await Task.sleep(for: Floater.lifetime)
            floaters.removeAll { ids.contains($0.id) }
        }
    }

    /// Names for the TV's quick-add sheet, most recently used first.
    func recentSingers(limit: Int = 12) -> [String] {
        Array(singers.prefix(limit))
    }

    /// Moves `name` to the front of `singers`, adding it if it's new. Empty names are ignored.
    func rememberSinger(_ name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(QueueStore.maxSinger))
        guard !name.isEmpty else { return }
        singers.removeAll { $0 == name }
        singers.insert(name, at: 0)
    }

    func notify(_ message: String) {
        noticeID += 1
        let id = noticeID
        notice = message
        Task {
            try? await Task.sleep(for: Self.noticeDuration)
            if noticeID == id { notice = nil }
        }
    }

    // MARK: - The loop

    private func loop() async {
        while !Task.isCancelled {
            await waitUntil { self.isActive && self.queue.firstReady() != nil }
            guard await countIn(), isActive, let entry = await store.startNext() else { continue }
            let outcome = await play(entry)
            if outcome == .released { await store.requeueNowPlaying() } else { await store.finishNowPlaying() }
            phase = .idle
        }
    }

    /// The 5 s "Up next" card. False when there's nothing left to start or the app went away.
    private func countIn() async -> Bool {
        startNowRequested = false  // drop a stale press
        for left in stride(from: Self.countInSeconds, through: 1, by: -1) {
            guard isActive, let next = queue.firstReady() else {
                phase = .idle
                return false
            }
            phase = .upNext(next, secondsLeft: left)
            let deadline = ContinuousClock.now + .seconds(1)
            while ContinuousClock.now < deadline, !startNowRequested, isActive {
                try? await Task.sleep(for: .milliseconds(50))
            }
            if startNowRequested { break }
        }
        return true
    }

    private func play(_ entry: QueueEntry) async -> Outcome {
        phase = .playing(entry)
        var key = entry.presetKey
        var startAt = 0.0
        for attempt in 0...1 {
            let streams: Streams
            do {
                guard let id = YouTubeURL.videoID(of: entry.url) else { throw StreamResolverError.noPlayableStream(videoID: entry.url, attempts: []) }
                streams = try await resolver.resolve(videoID: id)
            } catch {
                Logger.player.error("resolve failed for \(entry.url, privacy: .public): \(String(describing: error), privacy: .public)")
                notify("Couldn't load “\(entry.title)”. Skipping it.")
                return .error(httpCode: nil, position: 0, message: String(describing: error))
            }
            guard isActive else { return .released }
            let outcome = await player.play(streams, startKey: key, startAt: startAt)
            if case let .error(code, position, message) = outcome {
                Logger.player.error("playback failed for \(entry.url, privacy: .public): \(code ?? 0) \(message ?? "", privacy: .public)")
                if attempt == 0, let code, Self.retryCodes.contains(code) {
                    // The URLs expired: resolve again and resume where it stopped, at the same key.
                    key = player.key
                    startAt = position
                    continue
                }
                notify("Couldn't play “\(entry.title)”. Skipping it.")
            }
            return outcome
        }
        return .error(httpCode: nil, position: 0, message: nil)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        while !condition() {
            await withCheckedContinuation { waiters.append($0) }
        }
    }

    private func wake() {
        let ready = waiters
        waiters = []
        ready.forEach { $0.resume() }
    }
}
