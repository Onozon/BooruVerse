import Foundation

/// Generic Moebooru / Danbooru 1.13.x site (yande.re, konachan.com, …).
struct MoebooruSite: BooruSite, BooruBrowsing, BooruPools, BooruPopular {
    let siteID: String
    let displayName: String
    let baseURL: URL
    let apiFlavor: BooruAPIFlavor = .moebooru

    private var client: MoebooruClient {
        MoebooruClient(baseURL: baseURL, siteID: siteID)
    }

    init(host: String) {
        siteID = host
        displayName = host
        baseURL = URL(string: "https://\(host)") ?? URL(string: "https://yande.re")!
    }

    func fetchPosts(tags: String, page: Int, limit: Int) async throws -> [BooruPost] {
        try await client.fetchPosts(tags: tags, page: page, limit: limit)
    }

    func fetchPopular(period: PopularPeriod) async throws -> [BooruPost] {
        try await client.fetchPopular(period: period)
    }

    func fetchPools(query: String, page: Int) async throws -> [BooruPool] {
        try await client.fetchPools(query: query, page: page)
    }

    func fetchPoolPosts(poolID: Int, page: Int, limit: Int) async throws -> [BooruPost] {
        try await client.fetchPoolPosts(poolID: poolID, page: page, limit: limit)
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
