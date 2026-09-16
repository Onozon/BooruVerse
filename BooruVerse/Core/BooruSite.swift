import Foundation

/// A booru instance the app can browse (yande.re, danbooru, gelbooru, …).
/// Nonisolated: metadata is immutable and used from `@Sendable` fetch closures.
nonisolated protocol BooruSite: Sendable {
    var siteID: String { get }
    var displayName: String { get }
    var baseURL: URL { get }
    var apiFlavor: BooruAPIFlavor { get }
}

nonisolated enum BooruAPIFlavor: String, Codable, Sendable, CaseIterable {
    /// Danbooru 1.13.x / Moebooru (yande.re, konachan, …)
    case moebooru
    /// Danbooru 2.x (danbooru.donmai.us)
    case danbooru2
    /// Gelbooru / other XML APIs
    case gelbooru

    var title: String {
        switch self {
        case .moebooru: "Moebooru"
        case .danbooru2: "Danbooru"
        case .gelbooru: "Gelbooru"
        }
    }

    /// `GET` a single random post (Danbooru `random:N`, Moebooru `order:random`, Gelbooru `sort:random`).
    var supportsRandomPosts: Bool { true }

    /// Parent/child “other versions” of a post. Gelbooru exposes `parent_id` but no working `parent:` search.
    var supportsPostFamily: Bool {
        switch self {
        case .moebooru, .danbooru2: true
        case .gelbooru: false
        }
    }

    /// Dedicated pool list API (`pool.json`). Gelbooru only has `pool:<id>` post search; Danbooru pools are not wired yet.
    var supportsPools: Bool {
        self == .moebooru
    }

    var supportsPopular: Bool {
        self != .gelbooru
    }

    /// Search tokens that ask the site for a random post (combined with the rating filter).
    var randomPostTag: String {
        switch self {
        case .danbooru2: "random:1"
        case .moebooru: "order:random"
        case .gelbooru: "sort:random"
        }
    }
}

/// Read-only browsing operations shared by all backends.
nonisolated protocol BooruBrowsing: Sendable {
    func fetchPosts(tags: String, page: Int, limit: Int) async throws -> [BooruPost]
    func suggestTags(currentTags: [String], fragment: String, limit: Int) async throws -> [BooruTag]
    func fetchTagIndexPage(page: Int, limit: Int) async throws -> [BooruTag]
    func fetchTagTypes(for names: [String], onBatch: (@MainActor () -> Void)?) async -> [BooruTag]
}

extension BooruBrowsing {
    func fetchPost(id: Int) async throws -> BooruPost? {
        let posts = try await fetchPosts(tags: "id:\(id)", page: 1, limit: 1)
        return posts.first(where: { $0.id == id })
    }
}

/// Pool browsing operations (Moebooru `pool.json` / `pool/show.json`).
nonisolated protocol BooruPools: Sendable {
    func fetchPools(query: String, page: Int) async throws -> [BooruPool]
    func fetchPoolPosts(poolID: Int, page: Int, limit: Int) async throws -> [BooruPost]
}

/// Trending feed (Moebooru `post/popular_recent.json`).
nonisolated protocol BooruPopular: Sendable {
    func fetchPopular(period: PopularPeriod) async throws -> [BooruPost]
}
