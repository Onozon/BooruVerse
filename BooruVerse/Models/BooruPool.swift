import Foundation

nonisolated struct BooruPool: Identifiable, Hashable, Sendable {
    /// Host of the server this pool came from.
    let serverID: String
    /// Native (per-server) pool id.
    let id: Int
    let name: String
    let postCount: Int
    let description: String

    /// Globally-unique identity across servers.
    var globalID: String { "\(serverID)#\(id)" }

    var displayName: String {
        name.replacingOccurrences(of: "_", with: " ")
    }
}
