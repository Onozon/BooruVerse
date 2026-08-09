import Foundation

nonisolated private struct MoebooruPostDTO: Decodable {
    let id: Int
    let md5: String
    let tags: String
    let rating: String
    let score: Int
    let width: Int
    let height: Int
    let previewUrl: String?
    let sampleUrl: String?
    let fileUrl: String?
    let fileExt: String?
    let source: String?
    let createdAt: FlexibleAPIDate?

    func toModel(serverID: String) -> BooruPost {
        BooruPost(
            serverID: serverID,
            id: id,
            md5: md5,
            tags: tags.split(separator: " ").map(String.init),
            rating: BooruRating(raw: rating),
            score: score,
            width: width,
            height: height,
            previewURL: previewUrl.flatMap(URL.init(string:)),
            sampleURL: sampleUrl.flatMap(URL.init(string:)),
            fileURL: fileUrl.flatMap(URL.init(string:)),
            fileExt: fileExt ?? "",
            sourceURL: source.flatMap(URL.init(string:)),
            createdAt: createdAt?.date
        )
    }
}

nonisolated private struct MoebooruPoolDTO: Decodable {
    let id: Int
    let name: String
    let postCount: Int?
    let description: String?

    func toModel(serverID: String) -> BooruPool {
        BooruPool(
            serverID: serverID,
            id: id,
            name: name,
            postCount: postCount ?? 0,
            description: description ?? ""
        )
    }
}

nonisolated private struct MoebooruPoolShowDTO: Decodable {
    let posts: [MoebooruPostDTO]
}

nonisolated private struct MoebooruTagDTO: Decodable {
    let id: Int
    let name: String
    let count: Int
    let type: Int
    let ambiguous: Bool?

    func toModel() -> BooruTag {
        BooruTag(
            name: name,
            postCount: count,
            type: BooruTagType(moebooruRaw: type)
        )
    }
}

/// Moebooru / Danbooru 1.13.x client — see https://yande.re/help/api
nonisolated struct MoebooruClient: BooruBrowsing, BooruPools, BooruPopular {
    let baseURL: URL
    let siteID: String

    init(baseURL: URL, siteID: String) {
        self.baseURL = baseURL
        self.siteID = siteID
    }

    func fetchPosts(tags: String, page: Int, limit: Int = 40) async throws -> [BooruPost] {
        let cappedLimit = min(max(limit, 1), 100)
        let url = baseURL.appending(path: "post.json")
        let dtos: [MoebooruPostDTO] = try await BooruHTTPClient.getJSON(
            url: url,
            query: [
                "tags": tags,
                "page": String(page),
                "limit": String(cappedLimit)
            ]
        )
        return dtos.map { $0.toModel(serverID: siteID) }
    }

    func fetchPopular(period: PopularPeriod) async throws -> [BooruPost] {
        let url = baseURL.appending(path: "post/popular_recent.json")
        let dtos: [MoebooruPostDTO] = try await BooruHTTPClient.getJSON(
            url: url,
            query: ["period": period.rawValue]
        )
        return dtos.map { $0.toModel(serverID: siteID) }
    }

    func fetchPools(query: String, page: Int) async throws -> [BooruPool] {
        let url = baseURL.appending(path: "pool.json")
        var params = ["page": String(max(page, 1))]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            params["query"] = trimmed
        }
        let dtos: [MoebooruPoolDTO] = try await BooruHTTPClient.getJSON(url: url, query: params)
        return dtos.map { $0.toModel(serverID: siteID) }
    }

    func fetchPoolPosts(poolID: Int, page: Int, limit: Int = 40) async throws -> [BooruPost] {
        let url = baseURL.appending(path: "pool/show.json")
        let dto: MoebooruPoolShowDTO = try await BooruHTTPClient.getJSON(
            url: url,
            query: [
                "id": String(poolID),
                "page": String(max(page, 1))
            ]
        )
        return dto.posts.map { $0.toModel(serverID: siteID) }
    }

    func suggestTags(currentTags: [String], fragment: String, limit: Int = 20) async throws -> [BooruTag] {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Moebooru related-tags endpoint returns the best autocomplete for a tag context.
        var relatedQuery = currentTags
        relatedQuery.append(trimmed)
        let related = try await fetchRelatedTags(tags: relatedQuery.joined(separator: " "))

        let filtered = related
            .filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
            .filter { !currentTags.contains($0.name) }
            .sorted { $0.postCount > $1.postCount }

        if !filtered.isEmpty {
            let results = Array(filtered.prefix(limit))
            await applyTagTypes(results)
            return results
        }

        // Fallback: exact-name lookup via /tag.json
        let url = baseURL.appending(path: "tag.json")
        let dtos: [MoebooruTagDTO] = try await BooruHTTPClient.getJSON(
            url: url,
            query: [
                "name": trimmed,
                "limit": String(limit)
            ]
        )
        let results = dtos.map { $0.toModel() }.filter { !$0.name.isEmpty }
        await applyTagTypes(results)
        return results
    }

    func fetchTagTypes(for names: [String], onBatch: (@MainActor () -> Void)?) async -> [BooruTag] {
        let missing = names.filter { !$0.isEmpty }
        guard !missing.isEmpty else { return [] }

        let concurrency = 12
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
        let url = baseURL.appending(path: "tag.json")
        guard let dtos: [MoebooruTagDTO] = try? await BooruHTTPClient.getJSON(
            url: url,
            query: ["name": name, "limit": "1"]
        ),
        let match = dtos.first(where: { $0.name == name }) else {
            return nil
        }
        return match.toModel()
    }

    func fetchTagIndexPage(page: Int, limit: Int) async throws -> [BooruTag] {
        let cappedLimit = min(max(limit, 1), 1000)
        let url = baseURL.appending(path: "tag.json")
        let dtos: [MoebooruTagDTO] = try await BooruHTTPClient.getJSON(
            url: url,
            query: [
                "page": String(page),
                "limit": String(cappedLimit),
                "order": "name"
            ]
        )
        return dtos.map { $0.toModel() }.filter { !$0.name.isEmpty }
    }

    private func fetchRelatedTags(tags: String) async throws -> [BooruTag] {
        let url = baseURL.appending(path: "tag/related.json")
        let data = try await BooruHTTPClient.getData(url: url, query: ["tags": tags])

        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        // Response shape: { "query_tag": [["tag_name", "count"], ...], ... }
        var results: [BooruTag] = []
        for (_, value) in object {
            guard let pairs = value as? [[Any]] else { continue }
            for pair in pairs {
                guard pair.count >= 2,
                      let name = pair[0] as? String,
                      let count = parseCount(pair[1]) else { continue }
                results.append(BooruTag(name: name, postCount: count))
            }
        }

        var seen = Set<String>()
        return results.filter { seen.insert($0.name).inserted }
    }

    private func parseCount(_ value: Any) -> Int? {
        if let int = value as? Int { return int }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private func applyTagTypes(_ tags: [BooruTag]) async {
        await MainActor.run {
            TagIndexStore.shared.merge(tags, siteID: siteID)
        }
    }
}
