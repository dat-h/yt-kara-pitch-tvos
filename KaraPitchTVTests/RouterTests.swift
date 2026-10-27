import Foundation
import Synchronization
import Testing
@testable import KaraPitchTV

/// The Android API contract (Android SPEC §4.7, `KaraServer.kt`) against fake inputs.
struct RouterTests {
    private struct Failed: Error {}

    private final class PhaseBox: Sendable {
        private let value = Mutex(Phase.idle)
        var phase: Phase {
            get { value.withLock { $0 } }
            set { value.withLock { $0 = newValue } }
        }
    }

    private final class ReactionLog: Sendable {
        private let value = Mutex<[Reaction]>([])
        var all: [Reaction] { value.withLock { $0 } }
        func append(_ reaction: Reaction) { value.withLock { $0.append(reaction) } }
    }

    private final class Fixture: Sendable {
        let store: QueueStore
        let phase = PhaseBox()
        let reactions = ReactionLog()
        let router: Router

        init(searchFails: Bool = false) {
            let ids = Atomic(0)
            let store = QueueStore(
                check: { url, given in given ?? VideoMeta(title: "Title of \(url)", uploader: nil, thumb: nil, durationSec: 100) },
                newID: { "e\(ids.add(1, ordering: .relaxed).oldValue)" }
            )
            self.store = store
            let phase = phase
            let reactions = reactions
            router = Router(
                store: store,
                session: { SessionView(phase: phase.phase, player: PlayerSnapshot(positionMs: 1500, durationMs: 200_000, key: 2)) },
                search: { query, karaoke in
                    if searchFails { throw Failed() }
                    return [SearchResult(url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ", title: "\(query) \(karaoke)", durationSec: 212)]
                },
                webFile: { $0 == "index.html" ? Data("<html>".utf8) : $0 == "app.js" ? Data("js".utf8) : nil },
                react: { reaction in reactions.append(reaction) }
            )
        }

        func send(_ method: String, _ target: String, json: String? = nil) async -> HTTPResponse {
            let components = URLComponents(string: target)!
            var query: [String: String] = [:]
            for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
            return await router.handle(HTTPRequest(method: method, path: components.path, query: query, body: Data((json ?? "").utf8)))
        }
    }

    private func object(_ response: HTTPResponse) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: response.body) as? [String: Any])
    }

    private let link = "https://youtu.be/dQw4w9WgXcQ"

    @Test func addPastedLinkIsCreatedAndResolving() async throws {
        let f = Fixture()
        let r = await f.send("POST", "/api/queue", json: #"{"url":"\#(link)","singer":" Kim ","key":9,"extra":true}"#)
        #expect(r.status == 201)
        #expect(r.header("Access-Control-Allow-Origin") == "*")
        let e = try object(r)
        #expect(e["id"] as? String == "e0")
        #expect(e["url"] as? String == "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        #expect(e["title"] as? String == "Loading…")
        #expect(e["singer"] as? String == "Kim")
        #expect(e["presetKey"] as? Int == 6)
        #expect(e["status"] as? String == "RESOLVING")
        #expect(e["durationSec"] as? Int == 0)
        // explicitNulls = false: nil fields are left out.
        #expect(e["uploader"] == nil && e["thumb"] == nil && e["error"] == nil)
    }

    @Test func addFromSearchShowsItsDetailsWhileChecking() async throws {
        let f = Fixture()
        let r = await f.send("POST", "/api/queue", json: #"{"url":"\#(link)","title":"Found","channel":"Chan","thumb":"t.jpg","durationSec":180}"#)
        let e = try object(r)
        #expect(e["status"] as? String == "RESOLVING")
        #expect(e["title"] as? String == "Found")
        #expect(e["uploader"] as? String == "Chan")
        #expect(e["durationSec"] as? Int == 180)
    }

    @Test func addRejectsBadInput() async throws {
        let f = Fixture()
        let notYouTube = await f.send("POST", "/api/queue", json: #"{"url":"https://vimeo.com/1"}"#)
        #expect(notYouTube.status == 400)
        #expect(try object(notYouTube)["error"] as? String == "That isn't a YouTube video link")
        #expect(await f.send("POST", "/api/queue", json: #"{"singer":"x"}"#).status == 400)
        #expect(await f.send("POST", "/api/queue", json: "not json").status == 400)
    }

    @Test func fullQueueIsConflict() async throws {
        let f = Fixture()
        for _ in 0..<QueueStore.maxQueue {
            try await f.store.add(url: "u", singer: nil, key: nil, meta: VideoMeta(title: "t", uploader: nil, thumb: nil, durationSec: 1))
        }
        let r = await f.send("POST", "/api/queue", json: #"{"url":"\#(link)"}"#)
        #expect(r.status == 409)
        #expect(try object(r)["error"] as? String == "The queue is full")
    }

    @Test func stateShapeAndNotModified() async throws {
        let f = Fixture()
        let idle = try object(await f.send("GET", "/api/state"))
        #expect(idle["version"] as? Int == 0)
        #expect(idle["phase"] as? String == "idle")
        #expect((idle["queue"] as? [Any])?.isEmpty == true)
        #expect(idle["upNext"] == nil && idle["nowPlaying"] == nil && idle["player"] == nil)

        #expect(await f.send("GET", "/api/state?since=0").status == 304)
        #expect(await f.send("GET", "/api/state?since=0&player=1").status == 200)
        #expect(await f.send("GET", "/api/state?since=5").status == 200)

        let entry = try await f.store.add(url: "u", singer: "A", key: 1, meta: VideoMeta(title: "t", uploader: nil, thumb: nil, durationSec: 1))
        f.phase.phase = .upNext(entry, secondsLeft: 3)
        let upNext = try object(await f.send("GET", "/api/state?since=0"))
        #expect(upNext["phase"] as? String == "upnext")
        #expect((upNext["upNext"] as? [String: Any])?["entryId"] as? String == "e0")
        #expect((upNext["upNext"] as? [String: Any])?["secondsLeft"] as? Int == 3)
    }

    @Test func playerSnapshotOnlyWhenAskedAndPlaying() async throws {
        let f = Fixture()
        try await f.store.add(url: "u", singer: nil, key: nil, meta: VideoMeta(title: "t", uploader: nil, thumb: nil, durationSec: 1))
        #expect(try object(await f.send("GET", "/api/state?player=1"))["player"] == nil)  // nothing playing
        let entry = try #require(await f.store.startNext())
        f.phase.phase = .playing(entry)
        #expect(try object(await f.send("GET", "/api/state"))["player"] == nil)
        let state = try object(await f.send("GET", "/api/state?player=1"))
        #expect(state["phase"] as? String == "playing")
        #expect((state["nowPlaying"] as? [String: Any])?["id"] as? String == "e0")
        let player = try #require(state["player"] as? [String: Any])
        #expect(player["positionMs"] as? Int == 1500)
        #expect(player["durationMs"] as? Int == 200_000)
        #expect(player["paused"] as? Bool == false)
        #expect(player["buffering"] as? Bool == false)
        #expect(player["key"] as? Int == 2)
    }

    @Test func updateMoveDelete() async throws {
        let f = Fixture()
        for _ in 0..<2 { try await f.store.add(url: "u", singer: nil, key: nil, meta: VideoMeta(title: "t", uploader: nil, thumb: nil, durationSec: 1)) }

        let patched = await f.send("PATCH", "/api/queue/e0", json: #"{"singer":"Lee","key":-9}"#)
        #expect(patched.status == 200)
        #expect(try object(patched)["presetKey"] as? Int == -6)
        #expect(await f.send("PATCH", "/api/queue/nope", json: "{}").status == 404)

        #expect(await f.send("POST", "/api/queue/e1/move", json: #"{"index":0}"#).status == 204)
        #expect(await f.store.state.queue.map(\.id) == ["e1", "e0"])
        #expect(await f.send("POST", "/api/queue/nope/move", json: #"{"index":0}"#).status == 404)
        #expect(await f.send("POST", "/api/queue/e1/move", json: "{}").status == 400)

        #expect(await f.send("DELETE", "/api/queue/e1").status == 204)
        #expect(await f.send("DELETE", "/api/queue/e1").status == 404)
        #expect(await f.store.state.queue.map(\.id) == ["e0"])
    }

    @Test func search() async throws {
        let f = Fixture()
        let r = try object(await f.send("GET", "/api/search?q=%20abba%20&karaoke=0"))
        let results = try #require(r["results"] as? [[String: Any]])
        #expect(results.first?["title"] as? String == "abba false")
        #expect(results.first?["durationSec"] as? Int == 212)
        #expect(results.first?["channel"] == nil)
        #expect(try object(await f.send("GET", "/api/search?q=abba"))["results"].map { ($0 as? [[String: Any]])?.first?["title"] as? String } == "abba true")

        let empty = await f.send("GET", "/api/search?q=%20")
        #expect(empty.status == 400)
        #expect(try object(empty)["error"] as? String == "Type something to search for")
        #expect(await Fixture(searchFails: true).send("GET", "/api/search?q=abba").status == 502)
    }

    @Test func reactions() async {
        let f = Fixture()
        #expect(await f.send("POST", "/api/react/clap").status == 204)
        #expect(await f.send("POST", "/api/react/laugh").status == 204)
        #expect(await f.send("POST", "/api/react/whistle").status == 404)
        #expect(await f.send("GET", "/api/react/boo").status == 404)
        #expect(f.reactions.all == [.clap, .laugh])
    }

    @Test func corsPreflight() async {
        let r = await Fixture().send("OPTIONS", "/api/queue/e0")
        #expect(r.status == 200)
        #expect(r.header("Access-Control-Allow-Origin") == "*")
        #expect(r.header("Access-Control-Allow-Methods")?.contains("PATCH") == true)
        #expect(r.header("Access-Control-Allow-Headers") == "Content-Type")
    }

    @Test func staticFiles() async throws {
        let f = Fixture()
        let index = await f.send("GET", "/")
        #expect(index.status == 200)
        #expect(index.header("Content-Type") == "text/html; charset=UTF-8")
        #expect(index.body == Data("<html>".utf8))
        #expect(await f.send("GET", "/app.js").header("Content-Type") == "text/javascript; charset=UTF-8")
        #expect(await f.send("GET", "/missing.css").status == 404)
        #expect(await f.send("GET", "/../Info.plist").status == 404)
        #expect(await f.send("GET", "/api/nope").status == 404)
        #expect(await f.send("PUT", "/api/queue").status == 404)
    }

    @Test func bundledWebFilesAreServed() {
        #expect(WebFiles.data("index.html")?.isEmpty == false)
        #expect(WebFiles.data("app.js")?.isEmpty == false)
        #expect(WebFiles.data("style.css")?.isEmpty == false)
        #expect(WebFiles.data("Info.plist") == nil)
    }
}
