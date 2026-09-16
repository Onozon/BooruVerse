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
    /// Parent post id when this is a child “other version”. `nil` if none.
    let parentID: Int?
    /// True when the API reports this post has child versions.
    let hasChildren: Bool

    /// Globally-unique identity across servers. Use this as the key in all UI collections.
    var globalID: String { "\(serverID)#\(id)" }

    var tagList: [BooruTag] {
        tags.map { BooruTag(name: $0) }
    }

    /// Best still-image URL for grids and the photo viewer (sample, then original, then preview).
    var viewerURL: URL? {
        sampleURL ?? fileURL ?? previewURL
    }

    /// URL that should actually play for video / animated originals (sample is often a still JPEG).
    var playbackURL: URL? {
        if isVideo || prefersAnimatedOriginal {
            return fileURL ?? sampleURL ?? previewURL
        }
        return viewerURL
    }

    var normalizedFileExt: String {
        let trimmed = fileExt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !trimmed.isEmpty { return trimmed }
        for url in [fileURL, sampleURL, previewURL] {
            let ext = url?.pathExtension.lowercased() ?? ""
            if !ext.isEmpty { return ext }
        }
        return ""
    }

    static let videoExtensions: Set<String> = ["mp4", "webm", "mkv", "mov", "m4v", "avi"]

    var isVideo: Bool {
        Self.videoExtensions.contains(normalizedFileExt)
    }

    /// Native AVFoundation typically handles these; WebM/MKV fall back to WKWebView.
    var usesNativeAVPlayer: Bool {
        let urlExt = (fileURL ?? sampleURL)?.pathExtension.lowercased() ?? ""
        let ext = normalizedFileExt.isEmpty ? urlExt : normalizedFileExt
        if ["webm", "mkv"].contains(ext) || ["webm", "mkv"].contains(urlExt) {
            return false
        }
        return ["mp4", "mov", "m4v"].contains(ext) || ["mp4", "mov", "m4v"].contains(urlExt)
    }

    /// GIF / animated WebP / APNG — sample is often a still JPEG.
    var prefersAnimatedOriginal: Bool {
        switch normalizedFileExt {
        case "gif", "webp", "apng": true
        default: false
        }
    }

    /// True when a higher-quality original exists than `viewerURL`.
    var hasHigherQualityOriginal: Bool {
        if isVideo { return false }
        guard let fileURL else { return false }
        guard let viewerURL else { return true }
        return fileURL != viewerURL
    }

    /// Whether the post JSON hints at a parent/child family (still requires a family-capable API).
    var mayHaveFamily: Bool {
        (parentID ?? 0) > 0 || hasChildren
    }

    /// Id to query with `parent:<id>` (the parent, or this post if it is the root).
    var familyRootID: Int {
        parentID ?? id
    }

    /// Public HTML page for this post on its host (flavor-specific path).
    /// Scheme follows the post's media URLs when available (http custom hosts).
    func pageURL(flavor: BooruAPIFlavor) -> URL? {
        let scheme = (fileURL ?? sampleURL ?? previewURL)?.scheme?.lowercased()
        let useHTTP = scheme == "http"
        let prefix = useHTTP ? "http" : "https"
        switch flavor {
        case .moebooru:
            return URL(string: "\(prefix)://\(serverID)/post/show/\(id)")
        case .danbooru2:
            return URL(string: "\(prefix)://\(serverID)/posts/\(id)")
        case .gelbooru:
            return URL(string: "\(prefix)://\(serverID)/index.php?page=post&s=view&id=\(id)")
        }
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
