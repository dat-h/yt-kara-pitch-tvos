import Darwin
import Foundation

enum LocalAddress {
    /// This device's LAN IPv4 address (the first non-loopback one on en0/en1), or nil offline.
    static func ipv4() -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        var candidates: [(name: String, address: String)] = []
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let addr = entry.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET),
                entry.ifa_flags & UInt32(IFF_UP) != 0, entry.ifa_flags & UInt32(IFF_LOOPBACK) == 0
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            candidates.append((String(cString: entry.ifa_name), String(decoding: host.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)))
        }
        return candidates.first { $0.name == "en0" }?.address ?? candidates.first { $0.name == "en1" }?.address
            ?? candidates.first?.address
    }

    /// The phone URL shown on the TV.
    static func phoneURL() -> String? { ipv4().map { "http://\($0):\(HTTPServer.port)" } }
}
