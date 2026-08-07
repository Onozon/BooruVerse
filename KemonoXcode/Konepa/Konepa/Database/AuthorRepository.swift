import Foundation
import SwiftData

@MainActor
enum AuthorRepository {
    static let browsePageSize = 50
    static let maxRecentAuthors = 50
    static let maxRecentPosts = 50

    static func upsert(from result: KemonoArtistResult, in context: ModelContext) -> Author {
        let key = result.key
        let descriptor = FetchDescriptor<Author>(
            predicate: #Predicate { $0.key == key }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.apply(result)
            return existing
        }

        let author = Author(
            service: result.service,
            authorId: result.authorId,
            name: result.name,
            avatarURL: result.avatarURL,
            updatedAt: result.updatedAt
        )
        context.insert(author)
        return author
    }

    static func upsertBatch(from results: [KemonoArtistResult], in context: ModelContext) -> Int {
        var changed = 0
        for result in results {
            let key = result.key
            let descriptor = FetchDescriptor<Author>(
                predicate: #Predicate { $0.key == key }
            )

            if let existing = try? context.fetch(descriptor).first {
                existing.apply(result)
            } else {
                context.insert(
                    Author(
                        service: result.service,
                        authorId: result.authorId,
                        name: result.name,
                        avatarURL: result.avatarURL,
                        updatedAt: result.updatedAt
                    )
                )
            }
            changed += 1
        }
        return changed
    }

    static func search(query: String, in context: ModelContext, limit: Int = 100) throws -> [Author] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let needle = trimmed.lowercased()
        var descriptor = FetchDescriptor<Author>(
            predicate: #Predicate { author in
                author.nameLowercased.contains(needle)
                    || author.service.contains(needle)
                    || author.authorId.contains(needle)
            },
            sortBy: [SortDescriptor(\Author.name)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    static func fetchPage(offset: Int, limit: Int, in context: ModelContext) throws -> [Author] {
        var descriptor = FetchDescriptor<Author>(
            sortBy: [SortDescriptor(\Author.name)]
        )
        descriptor.fetchOffset = max(offset, 0)
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    static func count(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Author>())
    }

    static func countPosts(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Post>())
    }

    static func countSubscriptions(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Subscription>())
    }

    static func offlineAuthorCount(in context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<AuthorSyncState>())
    }

    /// Authors with cached/synced content only — not the full site catalog.
    static func fetchOfflineAuthors(in context: ModelContext, limit: Int = 100) throws -> [Author] {
        var descriptor = FetchDescriptor<AuthorSyncState>(
            sortBy: [SortDescriptor(\AuthorSyncState.authorKey)]
        )
        descriptor.fetchLimit = limit
        let states = try context.fetch(descriptor)
        return states.compactMap(\.author)
    }

    static func fetchRecentPosts(in context: ModelContext, limit: Int = 100) throws -> [Post] {
        var descriptor = FetchDescriptor<Post>(
            sortBy: [SortDescriptor(\Post.publishedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    static func fetchSubscriptions(in context: ModelContext, limit: Int = 200) throws -> [Subscription] {
        var descriptor = FetchDescriptor<Subscription>(
            sortBy: [SortDescriptor(\Subscription.subscribedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor)
    }

    static func subscribe(to author: Author, in context: ModelContext) {
        let key = author.key
        let descriptor = FetchDescriptor<Subscription>(
            predicate: #Predicate { $0.authorKey == key }
        )

        if (try? context.fetch(descriptor).first) != nil {
            return
        }

        context.insert(Subscription(author: author))
    }

    static func isSubscribed(_ author: Author, subscriptions: [Subscription]) -> Bool {
        subscriptions.contains { $0.authorKey == author.key }
    }

    static func recordRecentView(for author: Author, in context: ModelContext) {
        let key = author.key
        let descriptor = FetchDescriptor<RecentAuthor>(
            predicate: #Predicate { $0.authorKey == key }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.lastViewedAt = .now
            existing.author = author
        } else {
            context.insert(RecentAuthor(author: author))
        }

        trimRecentAuthors(in: context)
    }

    static func backfillSearchFields(in context: ModelContext, batchSize: Int = 5_000) {
        var offset = 0
        var changed = false

        while true {
            var descriptor = FetchDescriptor<Author>()
            descriptor.fetchOffset = offset
            descriptor.fetchLimit = batchSize

            let batch = (try? context.fetch(descriptor)) ?? []
            if batch.isEmpty { break }

            for author in batch {
                let normalized = author.name.lowercased()
                if author.nameLowercased != normalized {
                    author.nameLowercased = normalized
                    changed = true
                }
            }

            offset += batch.count
            if batch.count < batchSize { break }
        }

        if changed {
            try? context.save()
        }
    }

    static func catalogSyncState(in context: ModelContext) -> CatalogSyncState {
        let id = CatalogSyncState.singletonID
        let descriptor = FetchDescriptor<CatalogSyncState>(
            predicate: #Predicate { $0.id == id }
        )

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let state = CatalogSyncState()
        context.insert(state)
        return state
    }

    private static func trimRecentAuthors(in context: ModelContext) {
        var descriptor = FetchDescriptor<RecentAuthor>(
            sortBy: [SortDescriptor(\RecentAuthor.lastViewedAt, order: .reverse)]
        )
        descriptor.fetchOffset = maxRecentAuthors

        guard let stale = try? context.fetch(descriptor) else { return }
        for entry in stale {
            context.delete(entry)
        }
    }
}
