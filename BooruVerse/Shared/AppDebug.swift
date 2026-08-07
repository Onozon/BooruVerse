import Foundation
import OSLog

enum AppDebug {
    #if DEBUG
    static let isLoggingEnabled = true
    #else
    static let isLoggingEnabled = false
    #endif

    private static let logger = Logger(subsystem: "onozon.BooruVerse", category: "App")

    static func log(_ category: String, _ message: String) {
        guard isLoggingEnabled else { return }
        print("[\(category)] \(message)")
        // `.info` so `log stream` shows messages without private-data entitlements.
        logger.info("[\(category, privacy: .public)] \(message, privacy: .public)")
    }
}
