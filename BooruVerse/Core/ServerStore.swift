import SwiftUI

@MainActor
@Observable
final class ServerStore {
    static let shared = ServerStore()

    private(set) var servers: [BooruServer]
    private(set) var revision = 0

    var enabledServers: [BooruServer] {
        servers.filter(\.isEnabled)
    }

    var enabledCount: Int {
        enabledServers.count
    }

    private enum Keys {
        static let servers = "BooruVerse.servers.v1"
    }

    private static let seed: [BooruServer] = [
        BooruServer(host: "safebooru.org", flavor: .gelbooru, isEnabled: true, isBuiltIn: true),
        BooruServer(host: "yande.re", flavor: .moebooru, isEnabled: false, isBuiltIn: true),
        BooruServer(host: "konachan.com", flavor: .moebooru, isEnabled: false, isBuiltIn: true),
        BooruServer(host: "danbooru.donmai.us", flavor: .danbooru2, isEnabled: false, isBuiltIn: true),
        BooruServer(host: "gelbooru.com", flavor: .gelbooru, isEnabled: false, isBuiltIn: true)
    ]

    /// Selectable palette for per-server post borders (also the auto-assignment source).
    static let selectableColorHexes: [String] = [
        "#4A90E2", "#E23B3B", "#4CB56E", "#F29A3D", "#A170DB",
        "#EB73B3", "#40BABA", "#D9BF3D", "#5C6BC0", "#26A69A",
        "#EF5350", "#66BB6A", "#FFA726", "#AB47BC", "#EC407A",
        "#29B6F6", "#8D6E63", "#78909C", "#9CCC65", "#FF7043"
    ]

    private init() {
        if let data = UserDefaults.standard.data(forKey: Keys.servers),
           let decoded = try? JSONDecoder().decode([BooruServer].self, from: data),
           !decoded.isEmpty {
            servers = ServerStore.mergedWithBuiltIns(decoded)
        } else {
            servers = ServerStore.seed
        }

        if !servers.contains(where: \.isEnabled), !servers.isEmpty {
            servers[0].isEnabled = true
        }
    }

    /// Reconciles stored servers with the current built-in seed: built-ins come first in seed
    /// order (upgrading any host the user had added manually), followed by custom servers.
    /// User choices (enabled state, credentials) are preserved.
    private static func mergedWithBuiltIns(_ stored: [BooruServer]) -> [BooruServer] {
        var byHost: [String: BooruServer] = [:]
        for server in stored where byHost[server.host] == nil {
            byHost[server.host] = server
        }

        var result: [BooruServer] = []
        for builtin in seed {
            if var existing = byHost.removeValue(forKey: builtin.host) {
                existing.isBuiltIn = true
                existing.flavor = builtin.flavor
                result.append(existing)
            } else {
                result.append(builtin)
            }
        }

        // Preserve any user-added custom servers in their original order.
        for server in stored where byHost[server.host] != nil {
            result.append(server)
            byHost.removeValue(forKey: server.host)
        }

        return result
    }

    func contains(host: String) -> Bool {
        let normalized = ServerStore.normalize(host)
        return servers.contains { $0.host == normalized }
    }

    func setEnabled(_ enabled: Bool, host: String) {
        guard let index = servers.firstIndex(where: { $0.host == host }) else { return }
        if !enabled {
            let othersEnabled = servers.contains { $0.host != host && $0.isEnabled }
            guard othersEnabled else { return }
        }
        guard servers[index].isEnabled != enabled else { return }
        servers[index].isEnabled = enabled
        persist()
        revision += 1
    }

    func add(host: String, flavor: BooruAPIFlavor) {
        let normalized = ServerStore.normalize(host)
        guard !normalized.isEmpty, !servers.contains(where: { $0.host == normalized }) else { return }
        servers.append(BooruServer(host: normalized, flavor: flavor, isEnabled: true, isBuiltIn: false))
        persist()
        revision += 1
    }

    func updateCredentials(host: String, apiKey: String?, userID: String?) {
        guard let index = servers.firstIndex(where: { $0.host == host }) else { return }
        let cleanKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanUser = userID?.trimmingCharacters(in: .whitespacesAndNewlines)
        servers[index].apiKey = (cleanKey?.isEmpty ?? true) ? nil : cleanKey
        servers[index].userID = (cleanUser?.isEmpty ?? true) ? nil : cleanUser
        persist()
        revision += 1
    }

    func server(host: String) -> BooruServer? {
        servers.first { $0.host == host }
    }

    /// Updates a server's border color. Doesn't bump `revision` (no need to rebuild feeds/refetch);
    /// observers re-read the color via `@Observable` propagation.
    func updateColor(host: String, hex: String?) {
        guard let index = servers.firstIndex(where: { $0.host == host }) else { return }
        let clean = hex?.trimmingCharacters(in: .whitespacesAndNewlines)
        servers[index].colorHex = (clean?.isEmpty ?? true) ? nil : clean
        persist()
    }

    func remove(host: String) {
        guard let index = servers.firstIndex(where: { $0.host == host }) else { return }
        guard !servers[index].isBuiltIn else { return }

        let removingLastEnabled = servers[index].isEnabled
            && !servers.contains { $0.host != host && $0.isEnabled }
        servers.remove(at: index)
        if removingLastEnabled, !servers.isEmpty {
            servers[0].isEnabled = true
        }
        persist()
        revision += 1
    }

    func color(for serverID: String) -> Color {
        Color(hex: colorHex(for: serverID))
    }

    /// The effective border color hex for a server: the user's pick, or an auto-assigned palette entry.
    func colorHex(for serverID: String) -> String {
        if let server = servers.first(where: { $0.host == serverID }),
           let hex = server.colorHex, !hex.isEmpty {
            return hex
        }
        let index = servers.firstIndex(where: { $0.host == serverID }) ?? ServerStore.stableHash(serverID)
        return ServerStore.selectableColorHexes[index % ServerStore.selectableColorHexes.count]
    }

    static func normalize(_ host: String) -> String {
        var value = host.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let range = value.range(of: "://") {
            value = String(value[range.upperBound...])
        }
        if let slash = value.firstIndex(of: "/") {
            value = String(value[..<slash])
        }
        if value.hasPrefix("www.") {
            value = String(value.dropFirst(4))
        }
        return value
    }

    /// Deterministic (launch-stable) djb2 hash for palette fallback.
    private static func stableHash(_ string: String) -> Int {
        var hash = 5381
        for byte in string.utf8 {
            hash = (hash &* 33) &+ Int(byte)
        }
        return abs(hash)
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        UserDefaults.standard.set(data, forKey: Keys.servers)
    }
}

extension Color {
    /// Creates a color from a "#RRGGBB" (or "RRGGBB") hex string. Falls back to gray on bad input.
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased()
        var value: UInt64 = 0
        guard cleaned.count == 6, Scanner(string: cleaned).scanHexInt64(&value) else {
            self = .gray
            return
        }
        self = Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
