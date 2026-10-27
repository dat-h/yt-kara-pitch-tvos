import Foundation

/// A port of the Android app's `YouTubeUrls.kt`.
enum YouTubeURL {
    private static let hosts: Set<String> = ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com"]

    /// The canonical watch URL for a pasted YouTube link (watch, youtu.be, shorts, live, embed,
    /// music), or nil if it isn't one.
    static func normalize(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let components = URLComponents(string: text), let host = components.host?.lowercased() else { return nil }
        let segments = components.path.split(separator: "/").map(String.init)
        let id: String? =
            if host == "youtu.be" || host == "www.youtu.be" {
                segments.first
            } else if hosts.contains(host) {
                switch segments.first {
                case "watch": components.queryItems?.first { $0.name == "v" }?.value
                case "shorts", "live", "embed", "v": segments.count > 1 ? segments[1] : nil
                default: nil
                }
            } else {
                nil
            }
        guard let id, isVideoID(id) else { return nil }
        return "https://www.youtube.com/watch?v=\(id)"
    }

    /// The video ID in a canonical watch URL.
    static func videoID(of canonicalURL: String) -> String? {
        URLComponents(string: canonicalURL)?.queryItems?.first { $0.name == "v" }?.value
    }

    private static func isVideoID(_ s: String) -> Bool {
        s.count == 11 && s.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) && $0.isASCII || $0 == "_" || $0 == "-" }
    }
}
