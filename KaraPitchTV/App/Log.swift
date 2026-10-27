import os

extension Logger {
    private static let subsystem = "dev.ytkara.tv"

    static let resolver = Logger(subsystem: subsystem, category: "resolver")
    static let probe = Logger(subsystem: subsystem, category: "probe")
    static let player = Logger(subsystem: subsystem, category: "player")
    static let backdrop = Logger(subsystem: subsystem, category: "backdrop")
    static let server = Logger(subsystem: subsystem, category: "server")
}
