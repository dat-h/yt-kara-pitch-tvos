import Foundation

/// The phone web UI bundled under `Resources/web`, from the Android app plus the reaction bar.
enum WebFiles {
    /// Only these are served, so nothing else in the app bundle is reachable over the network.
    static let names: Set<String> = ["index.html", "app.js", "style.css"]

    static func data(_ path: String) -> Data? {
        guard names.contains(path) else { return nil }
        let url = Bundle.main.url(forResource: path, withExtension: nil, subdirectory: "web")
            ?? Bundle.main.url(forResource: path, withExtension: nil)
        return url.flatMap { try? Data(contentsOf: $0) }
    }
}
