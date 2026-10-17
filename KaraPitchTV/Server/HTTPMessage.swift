import Foundation

/// One parsed HTTP/1.1 request. Header names are lowercased.
struct HTTPRequest: Equatable, Sendable {
    var method: String
    /// The path without the query, percent-decoded.
    var path: String
    var query: [String: String] = [:]
    var headers: [String: String] = [:]
    var body = Data()

    enum Parse: Equatable {
        /// More bytes are needed.
        case incomplete
        case complete(HTTPRequest)
        case invalid
    }

    static let maxHeaderBytes = 16 * 1024
    static let maxBodyBytes = 1024 * 1024

    /// Parses `data` as it arrives: the request line, headers up to the blank line, then
    /// `Content-Length` bytes of body. Chunked bodies aren't supported (browsers don't send them).
    static func parse(_ data: Data) -> Parse {
        guard let headerEnd = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
            return data.count > maxHeaderBytes ? .invalid : .incomplete
        }
        guard let head = String(data: data[data.startIndex..<headerEnd.lowerBound], encoding: .utf8) else { return .invalid }
        var lines = head.components(separatedBy: "\r\n")
        let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
        guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1.") else { return .invalid }

        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { return .invalid }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }

        let length: Int
        if let value = headers["content-length"] {
            guard let n = Int(value), n >= 0, n <= maxBodyBytes else { return .invalid }
            length = n
        } else {
            length = 0
        }
        let bodyStart = headerEnd.upperBound
        guard data.count - (bodyStart - data.startIndex) >= length else { return .incomplete }

        let target = String(requestLine[1])
        guard let components = URLComponents(string: target), let path = components.percentEncodedPath.removingPercentEncoding else {
            return .invalid
        }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] where query[item.name] == nil {
            query[item.name] = item.value ?? ""
        }
        return .complete(
            HTTPRequest(
                method: String(requestLine[0]).uppercased(),
                path: path,
                query: query,
                headers: headers,
                body: Data(data[bodyStart..<(bodyStart + length)])
            ))
    }
}

struct HTTPResponse: Equatable, Sendable {
    var status: Int
    var headers: [(String, String)] = []
    var body = Data()

    static func == (a: HTTPResponse, b: HTTPResponse) -> Bool {
        a.status == b.status && a.body == b.body && a.headers.elementsEqual(b.headers) { $0 == $1 }
    }

    func header(_ name: String) -> String? {
        headers.first { $0.0.caseInsensitiveCompare(name) == .orderedSame }?.1
    }

    /// The bytes on the wire. Every response closes the connection.
    func serialized() -> Data {
        var head = "HTTP/1.1 \(status) \(Self.reason(status))\r\n"
        for (name, value) in headers { head += "\(name): \(value)\r\n" }
        head += "Content-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        return Data(head.utf8) + body
    }

    private static func reason(_ status: Int) -> String {
        switch status {
        case 200: "OK"
        case 201: "Created"
        case 204: "No Content"
        case 304: "Not Modified"
        case 400: "Bad Request"
        case 404: "Not Found"
        case 405: "Method Not Allowed"
        case 409: "Conflict"
        case 413: "Payload Too Large"
        case 500: "Internal Server Error"
        case 502: "Bad Gateway"
        default: "Status"
        }
    }
}
