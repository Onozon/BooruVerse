import Foundation

struct BooruPost: Identifiable, Hashable, Sendable {
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

enum BooruRating: String, Sendable {
    case safe = "s"
    case questionable = "q"
    case explicit = "e"

    init(raw: String) {
        self = BooruRating(rawValue: raw.lowercased()) ?? .safe
    }

    var label: String {
        switch self {
        case .safe: "Safe"
        case .questionable: "Questionable"
        case .explicit: "Explicit"
        }
    }
}
