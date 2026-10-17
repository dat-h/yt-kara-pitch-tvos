import Foundation
import Testing
@testable import KaraPitchTV

struct HTTPRequestTests {
    private func parse(_ text: String) -> HTTPRequest.Parse { HTTPRequest.parse(Data(text.utf8)) }

    @Test func parsesGetWithQueryAndHeaders() throws {
        guard case let .complete(r) = parse("GET /api/state?since=7&player=1 HTTP/1.1\r\nHost: tv\r\nX-Thing:  a b \r\n\r\n") else {
            Issue.record("not complete")
            return
        }
        #expect(r.method == "GET")
        #expect(r.path == "/api/state")
        #expect(r.query == ["since": "7", "player": "1"])
        #expect(r.headers["host"] == "tv")
        #expect(r.headers["x-thing"] == "a b")
        #expect(r.body.isEmpty)
    }

    @Test func waitsForHeadersAndBody() {
        #expect(parse("GET / HTTP/1.1\r\nHost: tv\r\n") == .incomplete)
        #expect(parse("POST /api/queue HTTP/1.1\r\nContent-Length: 10\r\n\r\n{\"url\"") == .incomplete)
    }

    @Test func readsContentLengthBody() {
        guard case let .complete(r) = parse("POST /api/queue HTTP/1.1\r\ncontent-length: 2\r\n\r\n{}") else {
            Issue.record("not complete")
            return
        }
        #expect(r.body == Data("{}".utf8))
    }

    @Test func decodesPercentEscapes() {
        guard case let .complete(r) = parse("GET /api/search?q=abba%20dancing+queen HTTP/1.1\r\n\r\n") else {
            Issue.record("not complete")
            return
        }
        #expect(r.query["q"] == "abba dancing+queen")
    }

    @Test(arguments: [
        "GARBAGE\r\n\r\n",
        "GET / SPDY/3\r\n\r\n",
        "GET / HTTP/1.1\r\nno colon here\r\n\r\n",
        "POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n",
        "POST / HTTP/1.1\r\nContent-Length: 99999999\r\n\r\n",
    ])
    func rejectsMalformed(_ text: String) {
        #expect(parse(text) == .invalid)
    }

    @Test func rejectsHugeHeaders() {
        #expect(parse("GET / HTTP/1.1\r\nX: " + String(repeating: "a", count: HTTPRequest.maxHeaderBytes)) == .invalid)
    }

    @Test func serializesResponse() {
        let text = String(decoding: HTTPResponse(status: 201, headers: [("Content-Type", "application/json")], body: Data("{}".utf8)).serialized(), as: UTF8.self)
        #expect(text == "HTTP/1.1 201 Created\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}")
    }
}
