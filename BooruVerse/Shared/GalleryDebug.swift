import Foundation

enum GalleryDebug {
    /// Verbose gallery/image loader logs. Off by default.
    nonisolated(unsafe) static var isEnabled = false

    /// On-screen HUD for gallery state (visible when `isEnabled`).
    nonisolated(unsafe) static var showHUD = false

    nonisolated static func log(_ message: String) {
        guard isEnabled else { return }
        print("[Gallery] \(message)")
    }

    nonisolated static func log(_ message: String, url: URL?) {
        log("\(message) url=\(url?.absoluteString ?? "nil")")
    }

    nonisolated static func state(
        _ label: String,
        postID: Int,
        phase: String,
        showFull: Bool,
        zoomed: Bool,
        navGestures: Bool
    ) {
        log("\(label) post=\(postID) phase=\(phase) full=\(showFull) zoomed=\(zoomed) nav=\(navGestures)")
    }
}
