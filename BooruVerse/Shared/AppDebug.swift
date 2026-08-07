import Foundation

enum AppDebug {
    #if DEBUG
    static let isLoggingEnabled = false
    #else
    static let isLoggingEnabled = false
    #endif

    static func log(_ category: String, _ message: String) {
        guard isLoggingEnabled else { return }
        print("[\(category)] \(message)")
    }
}
