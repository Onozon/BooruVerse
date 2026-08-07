import Foundation

/// Danbooru's modern media pipeline. The flat `*_file_url` fields are legacy and are `null`
/// for many posts (webp/avif assets, videos, ugoira, …); the real URLs live here.
private struct Danbooru2MediaAsset: Decodable {
    let variants: [Variant]?

    struct Variant: Decodable {
        let type: String?
        let url: String?
        let width: Int?
        let height: Int?
        let fileExt: String?
    }

    func url(ofType type: String) -> String? {
        variants?.first { $0.type == type }?.url
    }

    /// Smallest-to-largest thumbnail candidates for grid previews.
    var previewURL: String? {
        url(ofType: "360x360") ?? url(ofType: "180x180") ?? url(ofType: "720x720")
    }

    /// Mid-size candidates for the full-screen viewer.
    var sampleURL: String? {
        url(ofType: "sample") ?? url(ofType: "720x720") ?? url(ofType: "360x360")
    }

    var originalURL: String? {
        url(ofType: "original")
    }
}

private struct Danbooru2PostDTO: Decodable {
    let id: Int
    let md5: String?
    let fileUrl: String?
    let largeFileUrl: String?
    let previewFileUrl: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let tagString: String?
    let tagStringGeneral: String?
    let tagStringArtist: String?
    let tagStringCharacter: String?
    let tagStringCopyright: String?
    let tagStringMeta: String?
    let rating: String?
    let score: Int?
    let fileExt: String?
    let source: String?
    let mediaAsset: Danbooru2MediaAsset?

    func toModel(serverID: String) -> BooruPost {
        // Prefer the flat fields, fall back to media_asset variants when they're null
        // (restricted posts with no accessible media still resolve to nil → placeholder).
        let preview = firstURL(previewFileUrl, mediaAsset?.previewURL, largeFileUrl, fileUrl)
        let sample = firstURL(largeFileUrl, mediaAsset?.sampleURL, fileUrl, mediaAsset?.originalURL)
        let file = firstURL(fileUrl, mediaAsset?.originalURL, largeFileUrl)

        return BooruPost(
            serverID: serverID,
            id: id,
            md5: md5 ?? "",
            tags: (tagString ?? "").split(separator: " ").map(String.init),
            rating: Danbooru2PostDTO.rating(from: rating),
            score: score ?? 0,
            width: imageWidth ?? 0,
            height: imageHeight ?? 0,
            previewURL: preview,
            sampleURL: sample,
            fileURL: file,
            fileExt: fileExt ?? "",
            sourceURL: source.flatMap(URL.init(string:))
        )
    }

    private func firstURL(_ candidates: String?...) -> URL? {
        for candidate in candidates {
            if let candidate, !candidate.isEmpty, let url = URL(string: candidate) {
                return url
            }
        }
        return nil
    }

    /// Tag types are provided inline by Danbooru; no extra requests needed.
    func typedTags() -> [BooruTag] {
        func make(_ raw: String?, _ type: BooruTagType) -> [BooruTag] {
            (raw ?? "").split(separator: " ").map { BooruTag(name: String($0), postCount: 0, type: type) }
        }
        return make(tagStringGeneral, .general)
            + make(tagStringArtist, .artist)
            + make(tagStringCharacter, .character)
            + make(tagStringCopyright, .copyright)
            + make(tagStringMeta, .meta)
    }

    static func rating(from raw: String?) -> BooruRating {
        switch raw?.lowercased() {
        case "e": return .explicit
        case "q": return .questionable
        default: return .safe // g (general) / s (sensitive)
        }
    }
}

private struct Danbooru2TagDTO: Decodable {
    let name: String?
    let postCount: Int?
    let category: Int?

    func toModel() -> BooruTag? {
        guard let name, !name.isEmpty else { return nil }
        return BooruTag(name: name, postCount: postCount ?? 0, type: BooruTagType(moebooruRaw: category ?? 0))
    }
}

/// Danbooru 2.x client — see https://danbooru.donmai.us/wiki_pages/help:api
struct Danbooru2Client: BooruBrowsing, BooruPopular {
    let baseURL: URL
    let siteID: String
    /// Danbooru account login (username).
    let login: String?
    let apiKey: String?

    init(baseURL: URL, siteID: String, login: String? = nil, apiKey: String? = nil) {
        self.baseURL = baseURL
        self.siteID = siteID
        self.login = login
        self.apiKey = apiKey
    }

    /// Adds `login` + `api_key` when the user has provided credentials (optional on Danbooru).
    private func authorized(_ query: [String: String]) -> [String: String] {
        var result = query
        if let login, !login.isEmpty, let apiKey, !apiKey.isEmpty {
            result["login"] = login
            result["api_key"] = apiKey
        }
        return result
    }

    func fetchPosts(tags: String, page: Int, limit: Int = 40) async throws -> [BooruPost] {
        let cappedLimit = min(max(limit, 1), 200)
        let url = baseURL.appending(path: "posts.json")
        let dtos: [Danbooru2PostDTO] = try await BooruHTTPClient.getJSON(
            url: url,
            query: authorized([
                "tags": tags,
                "page": String(max(page, 1)),
                "limit": String(cappedLimit)
            ])
        )
        await mergeInlineTagTypes(dtos)
        return dtos.map { $0.toModel(serverID: siteID) }
    }

    func fetchPopular(period: PopularPeriod) async throws -> [BooruPost] {
        let url = baseURL.appending(path: "explore/posts/popular.json")
        let dtos: [Danbooru2PostDTO] = try await BooruHTTPClient.getJSON(
            url: url,
            query: authorized(["scale": Danbooru2Client.scale(for: period)])
        )
        await mergeInlineTagTypes(dtos)
        return dtos.map { $0.toModel(serverID: siteID) }
    }

    func suggestTags(currentTags: [String], fragment: String, limit: Int = 20) async throws -> [BooruTag] {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let url = baseURL.appending(path: "tags.json")
        let dtos: [Danbooru2TagDTO] = try await BooruHTTPClient.getJSON(
            url: url,
            query: authorized([
                "search[name_matches]": "\(trimmed)*",
                "search[order]": "count",
                "search[hide_empty]": "yes",
                "limit": String(limit)
            ])
        )
        let results = dtos.compactMap { $0.toModel() }
            .filter { !currentTags.contains($0.name) }
        await applyTagTypes(results)
        return Array(results.prefix(limit))
    }

    func fetchTagIndexPage(page: Int, limit: Int) async throws -> [BooruTag] {
        let url = baseURL.appending(path: "tags.json")
        let dtos: [Danbooru2TagDTO] = try await BooruHTTPClient.getJSON(
            url: url,
            query: authorized([
                "search[order]": "name",
                "page": String(max(page, 1)),
                "limit": String(min(max(limit, 1), 1000))
            ])
        )
        return dtos.compactMap { $0.toModel() }
    }

    func fetchTagTypes(for names: [String], onBatch: (@MainActor () -> Void)?) async -> [BooruTag] {
        let missing = names.filter { !$0.isEmpty }
        guard !missing.isEmpty else { return [] }

        let concurrency = 10
        var results: [BooruTag] = []

        for chunkStart in stride(from: 0, to: missing.count, by: concurrency) {
            let chunk = Array(missing[chunkStart..<min(chunkStart + concurrency, missing.count)])
            let batch = await withTaskGroup(of: BooruTag?.self) { group in
                for name in chunk {
                    group.addTask { await self.fetchSingleTagType(name: name) }
                }
                return await group.reduce(into: [BooruTag]()) { partial, tag in
                    if let tag { partial.append(tag) }
                }
            }
            results.append(contentsOf: batch)
            await applyTagTypes(batch)
            if let onBatch {
                await MainActor.run { onBatch() }
            }
        }
        return results
    }

    private func fetchSingleTagType(name: String) async -> BooruTag? {
        let url = baseURL.appending(path: "tags.json")
        guard let dtos: [Danbooru2TagDTO] = try? await BooruHTTPClient.getJSON(
            url: url,
            query: authorized(["search[name]": name, "limit": "1"])
        ),
        let match = dtos.compactMap({ $0.toModel() }).first(where: { $0.name == name }) else {
            return nil
        }
        return match
    }

    private static func scale(for period: PopularPeriod) -> String {
        switch period {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        }
    }

    private func mergeInlineTagTypes(_ dtos: [Danbooru2PostDTO]) async {
        let typed = dtos.flatMap { $0.typedTags() }
        guard !typed.isEmpty else { return }
        await applyTagTypes(typed)
    }

    private func applyTagTypes(_ tags: [BooruTag]) async {
        guard !tags.isEmpty else { return }
        await MainActor.run {
            TagIndexStore.shared.merge(tags, siteID: siteID)
        }
    }
}

/// Danbooru 2.x site (danbooru.donmai.us).
struct Danbooru2Site: BooruSite, BooruBrowsing, BooruPopular {
    let siteID: String
    let displayName: String
    let baseURL: URL
    let apiFlavor: BooruAPIFlavor = .danbooru2
    let login: String?
    let apiKey: String?

    private var client: Danbooru2Client {
        Danbooru2Client(baseURL: baseURL, siteID: siteID, login: login, apiKey: apiKey)
    }

    init(host: String, login: String? = nil, apiKey: String? = nil) {
        siteID = host
        displayName = host
        baseURL = URL(string: "https://\(host)") ?? URL(string: "https://danbooru.donmai.us")!
        self.login = login
        self.apiKey = apiKey
    }

    func fetchPosts(tags: String, page: Int, limit: Int) async throws -> [BooruPost] {
        try await client.fetchPosts(tags: tags, page: page, limit: limit)
    }

    func fetchPopular(period: PopularPeriod) async throws -> [BooruPost] {
        try await client.fetchPopular(period: period)
    }

    func suggestTags(currentTags: [String], fragment: String, limit: Int) async throws -> [BooruTag] {
        try await client.suggestTags(currentTags: currentTags, fragment: fragment, limit: limit)
    }

    func fetchTagIndexPage(page: Int, limit: Int) async throws -> [BooruTag] {
        try await client.fetchTagIndexPage(page: page, limit: limit)
    }

    func fetchTagTypes(for names: [String], onBatch: (@MainActor () -> Void)?) async -> [BooruTag] {
        await client.fetchTagTypes(for: names, onBatch: onBatch)
    }
}
