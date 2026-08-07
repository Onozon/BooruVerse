import Foundation

enum KemonoURLResolver {
    private static let cdnBase = "https://img.kemono.cr"
    private static let mediaSiteBase = URL(string: "https://kemono.cr")!

    /// Lightweight preview for post cards: `img.kemono.cr/thumbnail/data/…`
    static func previewURL(for pathOrURL: String?) -> String? {
        guard let path = extractMediaPath(pathOrURL) else { return nil }
        return "\(cdnBase)/thumbnail/data\(path)"
    }

    /// Site-relative path on the API mirror (not for direct media download on party/su).
    static func resolve(_ pathOrURL: String?, baseURL: URL = AppSettings.baseURL) -> String? {
        guard var raw = pathOrURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        raw = normalizeHost(raw)

        if isNodeCDN(raw), let path = extractMediaPath(raw), let preview = previewURL(for: path) {
            return preview
        }

        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return isUnreliableMirror(raw) ? previewURL(for: raw) ?? raw : raw
        }

        let site = mediaSiteURL(for: baseURL)
        if raw.hasPrefix("/") {
            var components = URLComponents(url: site, resolvingAgainstBaseURL: false)
            components?.path = raw
            components?.query = nil
            components?.fragment = nil
            return components?.url?.absoluteString
        }

        return site.appending(path: raw).absoluteString
    }

    static func fullMediaURL(for pathOrURL: String?, baseURL: URL = AppSettings.baseURL) -> String? {
        resolve(pathOrURL, baseURL: baseURL)
    }

    /// Ordered URLs to try when loading media.
    static func loadCandidates(for pathOrURL: String?, resolution: KemonoImageResolution) -> [String] {
        guard let path = extractMediaPath(pathOrURL) else {
            return []
        }

        switch resolution {
        case .preview:
            return uniqueURLs([previewURL(for: path)].compactMap { $0 })

        case .full:
            var list: [String] = []
            if let full = resolve(path, baseURL: mediaSiteBase) {
                list.append(full)
            }
            if let preview = previewURL(for: path) {
                list.append(preview)
            }
            if AppSettings.baseURL != mediaSiteBase,
               !isUnreliableMirrorHost(AppSettings.baseURL.host),
               let userMirror = resolve(path, baseURL: AppSettings.baseURL) {
                list.append(userMirror)
            }
            return uniqueURLs(list.filter { !isNodeCDN($0) && !isUnreliableMirror($0) })
        }
    }

    /// Prefer img CDN for thumbnails; avoid party/su mirrors that often fail DNS/TLS.
    static func imageURL(for pathOrURL: String?) -> String? {
        previewURL(for: pathOrURL) ?? avatarURL(for: pathOrURL)
    }

    static func avatarURL(for pathOrURL: String?) -> String? {
        guard var raw = pathOrURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        raw = normalizeHost(raw)
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return raw
        }
        if raw.hasPrefix("/icons/") {
            return "\(cdnBase)\(raw)"
        }
        if raw.hasPrefix("icons/") {
            return "\(cdnBase)/\(raw)"
        }
        return nil
    }

    static func normalizeHost(_ url: String) -> String {
        url
            .replacingOccurrences(of: "img.kemono.su", with: "img.kemono.cr")
            .replacingOccurrences(of: "://kemono.su", with: "://kemono.cr")
            .replacingOccurrences(of: "://kemono.party", with: "://kemono.cr")
    }

    static func isNodeCDN(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        guard host.contains("kemono") else { return false }
        return host.range(of: #"^n\d+\."#, options: .regularExpression) != nil
    }

    static func isUnreliableMirror(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return isUnreliableMirrorHost(host)
    }

    private static func isUnreliableMirrorHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "kemono.party" || host == "kemono.su"
    }

    private static func mediaSiteURL(for baseURL: URL) -> URL {
        isUnreliableMirrorHost(baseURL.host) ? mediaSiteBase : baseURL
    }

    private static func uniqueURLs(_ urls: [String]) -> [String] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0).inserted }
    }

    static func extractMediaPath(_ pathOrURL: String?) -> String? {
        guard var raw = pathOrURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }

        raw = normalizeHost(raw)

        if raw.contains("/thumbnail/data/"), let url = URL(string: raw) {
            let path = url.path
            if let suffix = path.split(separator: "/thumbnail/data/", maxSplits: 1).last {
                return "/\(suffix)"
            }
        }

        if raw.hasPrefix("http://") || raw.hasPrefix("https://"), let url = URL(string: raw) {
            var path = url.path
            if path.hasPrefix("/data/") {
                path = String(path.dropFirst(5))
                return path.hasPrefix("/") ? path : "/\(path)"
            }
            if isMediaPath(path) {
                return path
            }
            return nil
        }

        if raw.hasPrefix("/") {
            return isMediaPath(raw) ? raw : nil
        }

        let withSlash = "/\(raw)"
        return isMediaPath(withSlash) ? withSlash : nil
    }

    private static func isMediaPath(_ path: String) -> Bool {
        let lower = path.lowercased()
        let extensions = [".jpg", ".jpeg", ".png", ".gif", ".webp", ".mp4", ".webm"]
        return extensions.contains { lower.hasSuffix($0) } && path.count > 10
    }
}

enum KemonoImageResolution: Sendable {
    case preview
    case full
}
