import Foundation
import os

/// What the API needs from the TV session, read on the main actor.
struct SessionView: Sendable {
    var phase: Phase
    var player: PlayerSnapshot
}

/// Routes one request to the queue, the session and the bundled web UI, answering exactly as the
/// Android app's Ktor server does. `POST /api/react/{reaction}` is TV-only.
struct Router: Sendable {
    let store: QueueStore
    let session: @Sendable () async -> SessionView
    let search: @Sendable (_ query: String, _ addKaraoke: Bool) async throws -> [SearchResult]
    /// The bytes of a bundled web file (`index.html`, `app.js`, …), or nil.
    let webFile: @Sendable (_ path: String) -> Data?
    /// Plays an audience reaction on the TV.
    var react: @Sendable (Reaction) async -> Void = { _ in }

    func handle(_ request: HTTPRequest) async -> HTTPResponse {
        var response = await route(request)
        // CORS open to any origin, like Ktor's `anyHost()`.
        response.headers.append(("Access-Control-Allow-Origin", "*"))
        return response
    }

    private func route(_ request: HTTPRequest) async -> HTTPResponse {
        let segments = request.path.split(separator: "/").map(String.init)
        if request.method == "OPTIONS" {
            return HTTPResponse(status: 200, headers: [
                ("Access-Control-Allow-Methods", "GET, POST, PATCH, DELETE, OPTIONS"),
                ("Access-Control-Allow-Headers", "Content-Type"),
                ("Access-Control-Max-Age", "86400"),
            ])
        }
        guard segments.first == "api" else {
            return request.method == "GET" ? staticFile(segments) : notFound()
        }
        let api = Array(segments.dropFirst())
        switch (request.method, api.count) {
        case ("GET", 1) where api[0] == "state":
            return await state(request)
        case ("GET", 1) where api[0] == "search":
            return await search(request)
        case ("POST", 1) where api[0] == "queue":
            return await add(request)
        case ("PATCH", 2) where api[0] == "queue":
            guard let body = decode(UpdateRequest.self, request) else { return badRequest() }
            guard let entry = await store.update(id: api[1], singer: body.singer, key: body.key) else { return notFound() }
            return json(200, entry)
        case ("POST", 3) where api[0] == "queue" && api[2] == "move":
            guard let body = decode(MoveRequest.self, request) else { return badRequest() }
            return await store.move(id: api[1], to: body.index) ? HTTPResponse(status: 204) : notFound()
        case ("DELETE", 2) where api[0] == "queue":
            return await store.remove(id: api[1]) ? HTTPResponse(status: 204) : notFound()
        case ("POST", 2) where api[0] == "react":
            guard let reaction = Reaction(rawValue: api[1]) else { return notFound() }
            await react(reaction)
            return HTTPResponse(status: 204)
        default:
            return notFound()
        }
    }

    private func state(_ request: HTTPRequest) async -> HTTPResponse {
        let queue = await store.state
        let withPlayer = request.query["player"] == "1"
        if !withPlayer, let since = request.query["since"].flatMap(Int64.init), since == queue.version {
            return HTTPResponse(status: 304)
        }
        let view = await session()
        let phase: String
        var upNext: UpNextDTO?
        switch view.phase {
        case .idle: phase = "idle"
        case let .upNext(entry, secondsLeft):
            phase = "upnext"
            upNext = UpNextDTO(entryId: entry.id, secondsLeft: secondsLeft)
        case .playing: phase = "playing"
        }
        return json(200, StateResponse(
            version: queue.version,
            phase: phase,
            upNext: upNext,
            nowPlaying: queue.nowPlaying,
            player: withPlayer && queue.nowPlaying != nil ? view.player : nil,
            queue: queue.queue
        ))
    }

    private func search(_ request: HTTPRequest) async -> HTTPResponse {
        let query = (request.query["q"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return json(400, ErrorResponse(error: "Type something to search for")) }
        do {
            return json(200, SearchResponse(results: try await search(query, request.query["karaoke"] != "0")))
        } catch {
            Logger.server.error("search failed for '\(query, privacy: .public)': \(String(describing: error), privacy: .public)")
            return json(502, ErrorResponse(error: "YouTube search failed"))
        }
    }

    private func add(_ request: HTTPRequest) async -> HTTPResponse {
        guard let body = decode(AddRequest.self, request) else { return badRequest() }
        guard let url = YouTubeURL.normalize(body.url) else { return json(400, ErrorResponse(error: "That isn't a YouTube video link")) }
        let meta = body.title.flatMap { title in
            title.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : VideoMeta(title: String(title.prefix(200)), uploader: body.channel, thumb: body.thumb, durationSec: body.durationSec ?? 0)
        }
        do {
            return json(201, try await store.add(url: url, singer: body.singer, key: body.key, meta: meta))
        } catch {
            return json(409, ErrorResponse(error: String(describing: error)))
        }
    }

    private func staticFile(_ segments: [String]) -> HTTPResponse {
        let path = segments.isEmpty ? "index.html" : segments.joined(separator: "/")
        guard !path.contains(".."), let data = webFile(path) else { return notFound() }
        return HTTPResponse(status: 200, headers: [("Content-Type", Self.contentType(path))], body: data)
    }

    static func contentType(_ path: String) -> String {
        switch (path as NSString).pathExtension {
        case "html": "text/html; charset=UTF-8"
        case "css": "text/css; charset=UTF-8"
        case "js": "text/javascript; charset=UTF-8"
        case "svg": "image/svg+xml"
        case "png": "image/png"
        case "json", "webmanifest": "application/json"
        default: "application/octet-stream"
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ request: HTTPRequest) -> T? {
        try? JSONDecoder().decode(type, from: request.body)
    }

    private func json(_ status: Int, _ value: some Encodable) -> HTTPResponse {
        let data = (try? JSONEncoder().encode(value)) ?? Data("{}".utf8)
        return HTTPResponse(status: status, headers: [("Content-Type", "application/json; charset=UTF-8")], body: data)
    }

    private func badRequest() -> HTTPResponse { json(400, ErrorResponse(error: "Bad request")) }

    private func notFound() -> HTTPResponse { json(404, ErrorResponse(error: "Not found")) }
}
