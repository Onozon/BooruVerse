import Foundation

/// Opt out of module-wide MainActor default — posts cross task-group / actor boundaries.
nonisolated struct BooruPost: Identifiable, Hashable, Sendable {
    /// Host of the server this post came from (e.g. "yande.re"). Used for cross-server identity.
    let serverID: String
    /// Native (per-server) post id. NOT unique across servers.
    let id: Int
    let md5: String
    let tags: [String]
    let rating: BooruRating
    let score: Int
    let width: Int
    let height: Int
    let previewURL: URL?
    let sampleURL: URL?
    let fileURL: URL?
    let fileExt: String
    let sourceURL: URL?
    /// Publication time when the API provides it (used for Personal feed ordering).
    let createdAt: Date?

    /// Globally-unique identity across servers. Use this as the key in all UI collections.
    var globalID: String { "\(serverID)#\(id)" }

    var tagList: [BooruTag] {
        tags.map { BooruTag(name: $0) }
    }

    /// Best URL for fullscreen viewing (sample, then original, then preview).
    var viewerURL: URL? {
        sampleURL ?? fileURL ?? previewURL
    }

    /// True when a higher-quality original exists than `viewerURL`.
    var hasHigherQualityOriginal: Bool {
        guard let fileURL else { return false }
        guard let viewerURL else { return true }
        return fileURL != viewerURL
    }
}

nonisolated enum BooruRating: String, Sendable {
    /// Moebooru `s` / Danbooru `g` / Gelbooru general-safe.
    case safe = "s"
    /// Danbooru `s` (sensitive) — not Safe Only.
    case sensitive = "sensitive"
    case questionable = "q"
    case explicit = "e"

    init(raw: String) {
        switch raw.lowercased() {
        case "s", "safe", "g", "general":
            self = .safe
        case "sensitive":
            self = .sensitive
        case "q", "questionable":
            self = .questionable
        case "e", "explicit":
            self = .explicit
        default:
            self = .safe
        }
    }

    var label: String {
        switch self {
        case .safe: "Safe"
        case .sensitive: "Sensitive"
        case .questionable: "Questionable"
        case .explicit: "Explicit"
        }
    }
}
