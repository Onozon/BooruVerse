import Foundation

private struct GelbooruPostResponse: Decodable {
    let post: [GelbooruPostDTO]?
}

private struct GelbooruPostDTO: Decodable {
    let id: Int
    let md5: String?
    let fileUrl: String?
    let previewUrl: String?
    let sampleUrl: String?
    let width: Int?
    let height: Int?
    let tags: String?
    let rating: String?
    let score: Int?
    let source: String?

    func toModel(serverID: String) -> BooruPost {
        let ext = fileUrl.flatMap { URL(string: $0)?.pathExtension } ?? ""
        return BooruPost(
            serverID: serverID,
            id: id,
            md5: md5 ?? "",
            tags: (tags ?? "").split(separator: " ").map(String.init),
            rating: GelbooruPostDTO.rating(from: rating),
            score: score ?? 0,
            width: width ?? 0,
            height: height ?? 0,
            previewURL: previewUrl.flatMap(URL.init(string:)),
            sampleURL: sampleUrl.flatMap(URL.init(string:)),
            fileURL: fileUrl.flatMap(URL.init(string:)),
            fileExt: ext,
            sourceURL: source.flatMap(URL.init(string:))
        )
    }

    static func rating(from raw: String?) -> BooruRating {
        switch raw?.lowercased() {
        case "explicit", "e": return .explicit
        case "questionable", "q": return .questionable
        default: return .safe // general / safe / sensitive
        }
    }
}

private struct GelbooruTagResponse: Decodable {
    let tag: [GelbooruTagDTO]?
}

private struct GelbooruTagDTO: Decodable {
    let name: String?
    let count: Int?
    let type: Int?

    func toModel() -> BooruTag? {
        guard let name, !name.isEmpty else { return nil }
        return BooruTag(name: name, postCount: count ?? 0, type: BooruTagType(moebooruRaw: type ?? 0))
    }
}

/// Gelbooru 0.2 client — see https://gelbooru.com/index.php?page=wiki&s=view&id=18780
struct GelbooruClient: BooruBrowsing {
    let baseURL: URL
    let siteID: String
    let apiKey: String?
    let userID: String?

    init(baseURL: URL, siteID: String, apiKey: String? = nil, userID: String? = nil) {
        self.baseURL = baseURL
        self.siteID = siteID
        self.apiKey = apiKey
        self.userID = userID
    }

    /// Gelbooru requires `api_key` + `user_id` on every request (anonymous access returns 401).
    private func authorized(_ query: [String: String]) -> [String: String] {
        var result = query
        if let apiKey, !apiKey.isEmpty { result["api_key"] = apiKey }
        if let userID, !userID.isEmpty { result["user_id"] = userID }
        return result
    }

    func fetchPosts(tags: String, page: Int, limit: Int = 40) async throws -> [BooruPost] {
        let cappedLimit = min(max(limit, 1), 100)
        let pid = max(page - 1, 0) // Gelbooru paginates with a 0-based page index.
        let url = baseURL.appending(path: "index.php")
        let data = try await BooruHTTPClient.getData(
            url: url,
            query: authorized([
                "page": "dapi",
                "s": "post",
                "q": "index",
                "json": "1",
                "tags": tags,
                "pid": String(pid),
                "limit": String(cappedLimit)
            ])
        )
        return GelbooruClient.decodePosts(data).map { $0.toModel(serverID: siteID) }
    }

    func suggestTags(currentTags: [String], fragment: String, limit: Int = 20) async throws -> [BooruTag] {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let url = baseURL.appending(path: "index.php")
        let data = try await BooruHTTPClient.getData(
            url: url,
            query: authorized([
                "page": "dapi",
                "s": "tag",
                "q": "index",
                "json": "1",
                "name_pattern": "%\(trimmed)%",
                "orderby": "count",
                "limit": String(limit)
            ])
        )
        let results = GelbooruClient.decodeTags(data)
            .compactMap { $0.toModel() }
            .filter { !currentTags.contains($0.name) }
            .sorted { $0.postCount > $1.postCount }
        await applyTagTypes(results)
        return Array(results.prefix(limit))
    }

    func fetchTagIndexPage(page: Int, limit: Int) async throws -> [BooruTag] {
        let url = baseURL.appending(path: "index.php")
        let data = try await BooruHTTPClient.getData(
            url: url,
            query: authorized([
                "page": "dapi",
                "s": "tag",
                "q": "index",
                "json": "1",
                "orderby": "name",
                "pid": String(max(page - 1, 0)),
                "limit": String(min(max(limit, 1), 1000))
            ])
        )
        return GelbooruClient.decodeTags(data).compactMap { $0.toModel() }
    }

    func fetchTagTypes(for names: [String], onBatch: (@MainActor () -> Void)?) async -> [BooruTag] {
        let missing = names.filter { !$0.isEmpty }
        guard !missing.isEmpty else { return [] }

        var results: [BooruTag] = []
        let chunkSize = 100
        for chunkStart in stride(from: 0, to: missing.count, by: chunkSize) {
            let chunk = Array(missing[chunkStart..<min(chunkStart + chunkSize, missing.count)])
            let batch = await fetchTagChunk(chunk)
            results.append(contentsOf: batch)
            await applyTagTypes(batch)
            if let onBatch {
                await MainActor.run { onBatch() }
            }
        }
        return results
    }

    private func fetchTagChunk(_ names: [String]) async -> [BooruTag] {
        let url = baseURL.appending(path: "index.php")
        guard let data = try? await BooruHTTPClient.getData(
            url: url,
            query: authorized([
                "page": "dapi",
                "s": "tag",
                "q": "index",
                "json": "1",
                "names": names.joined(separator: " ")
            ])
        ) else {
            return []
        }
        return GelbooruClient.decodeTags(data).compactMap { $0.toModel() }
    }

    private func applyTagTypes(_ tags: [BooruTag]) async {
        guard !tags.isEmpty else { return }
        await MainActor.run {
            TagIndexStore.shared.merge(tags, siteID: siteID)
        }
    }

    private static func decodePosts(_ data: Data) -> [GelbooruPostDTO] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let wrapper = try? decoder.decode(GelbooruPostResponse.self, from: data) {
            return wrapper.post ?? []
        }
        if let array = try? decoder.decode([GelbooruPostDTO].self, from: data) {
            return array
        }
        return []
    }

    private static func decodeTags(_ data: Data) -> [GelbooruTagDTO] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        if let wrapper = try? decoder.decode(GelbooruTagResponse.self, from: data) {
            return wrapper.tag ?? []
        }
        if let array = try? decoder.decode([GelbooruTagDTO].self, from: data) {
            return array
        }
        return []
    }
}

/// Gelbooru site (gelbooru.com). No pools/popular feed support.
struct GelbooruSite: BooruSite, BooruBrowsing {
    let siteID: String
    let displayName: String
    let baseURL: URL
    let apiFlavor: BooruAPIFlavor = .gelbooru
    let apiKey: String?
    let userID: String?

    private var client: GelbooruClient {
        GelbooruClient(baseURL: baseURL, siteID: siteID, apiKey: apiKey, userID: userID)
    }

    init(host: String, apiKey: String? = nil, userID: String? = nil) {
        siteID = host
        displayName = host
        baseURL = URL(string: "https://\(host)") ?? URL(string: "https://gelbooru.com")!
        self.apiKey = apiKey
        self.userID = userID
    }

    func fetchPosts(tags: String, page: Int, limit: Int) async throws -> [BooruPost] {
        try await client.fetchPosts(tags: tags, page: page, limit: limit)
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
