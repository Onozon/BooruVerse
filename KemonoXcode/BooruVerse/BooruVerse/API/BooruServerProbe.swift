import Foundation

enum BooruServerProbeError: LocalizedError {
    case unreachable
    case notABooru

    var errorDescription: String? {
        switch self {
        case .unreachable: "Couldn't reach this host."
        case .notABooru: "This host doesn't look like a supported booru API."
        }
    }
}

/// Detects the API flavor of a host by probing known endpoints, and verifies it actually responds.
enum BooruServerProbe {
    /// Returns the detected flavor, or throws if the host is unreachable / not a supported booru.
    static func detectFlavor(host: String) async throws -> BooruAPIFlavor {
        let normalized = ServerStore.normalize(host)
        guard let base = URL(string: "https://\(normalized)") else {
            throw BooruServerProbeError.unreachable
        }

        // Order matters: try the most specific/structured responses first.
        if await probeMoebooru(base: base) { return .moebooru }
        if await probeDanbooru2(base: base) { return .danbooru2 }
        if await probeGelbooru(base: base) { return .gelbooru }

        throw BooruServerProbeError.notABooru
    }

    private static func probeMoebooru(base: URL) async -> Bool {
        let url = base.appending(path: "post.json")
        guard let data = try? await BooruHTTPClient.getData(url: url, query: ["limit": "1"]) else {
            return false
        }
        // Moebooru returns a JSON array of posts with an integer "id".
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        return json.first?["id"] is Int || json.isEmpty
    }

    private static func probeDanbooru2(base: URL) async -> Bool {
        let url = base.appending(path: "posts.json")
        guard let data = try? await BooruHTTPClient.getData(url: url, query: ["limit": "1"]) else {
            return false
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        // Danbooru posts carry "tag_string" / "file_ext" keys.
        guard let first = json.first else { return json.isEmpty }
        return first["tag_string"] != nil || first["file_ext"] != nil
    }

    private static func probeGelbooru(base: URL) async -> Bool {
        let url = base.appending(path: "index.php")
        guard let data = try? await BooruHTTPClient.getData(
            url: url,
            query: ["page": "dapi", "s": "post", "q": "index", "json": "1", "limit": "1"]
        ) else {
            return false
        }
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object["post"] != nil || object["@attributes"] != nil
        }
        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return array.first?["id"] != nil || array.isEmpty
        }
        return false
    }
}
