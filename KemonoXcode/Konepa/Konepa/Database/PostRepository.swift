import Foundation
import SwiftData

@MainActor
enum PostRepository {
    static func upsert(from result: KemonoPostResult, author: Author, in context: ModelContext) -> Post {
        let key = result.key
        let descriptor = FetchDescriptor<Post>(
            predicate: #Predicate { $0.key == key }
        )

        let previewURL = KemonoURLResolver.previewURL(for: result.previewURL)

        if let existing = try? context.fetch(descriptor).first {
            existing.title = result.title
            existing.publishedAt = result.publishedAt
            existing.previewURL = previewURL
            existing.author = author
            return existing
        }

        let post = Post(
            service: result.service,
            authorId: result.authorId,
            postId: result.postId,
            title: result.title,
            publishedAt: result.publishedAt,
            previewURL: previewURL,
            author: author
        )
        context.insert(post)
        return post
    }

    static func upsertBatch(
        from results: [KemonoPostResult],
        author: Author,
        in context: ModelContext
    ) -> Int {
        let service = author.service
        let authorId = author.authorId
        let descriptor = FetchDescriptor<Post>(
            predicate: #Predicate { $0.service == service && $0.authorId == authorId }
        )
        let existingPosts = (try? context.fetch(descriptor)) ?? []
        var postsByKey = Dictionary(uniqueKeysWithValues: existingPosts.map { ($0.key, $0) })

        for result in results {
            let previewURL = KemonoURLResolver.previewURL(for: result.previewURL)

            if let post = postsByKey[result.key] {
                post.title = result.title
                post.publishedAt = result.publishedAt
                post.previewURL = previewURL
                post.author = author
            } else {
                let post = Post(
                    service: result.service,
                    authorId: result.authorId,
                    postId: result.postId,
                    title: result.title,
                    publishedAt: result.publishedAt,
                    previewURL: previewURL,
                    author: author
                )
                context.insert(post)
                postsByKey[result.key] = post
            }
        }

        return results.count
    }

    static func updateSyncState(
        for author: Author,
        posts: [KemonoPostResult],
        isFullySynced: Bool,
        in context: ModelContext
    ) {
        let syncState: AuthorSyncState
        if let existing = author.syncState {
            syncState = existing
        } else {
            syncState = AuthorSyncState(author: author)
            context.insert(syncState)
        }

        syncState.isFullySynced = isFullySynced
        syncState.lastSyncedAt = .now

        if let newest = posts.map(\.publishedAt).max() {
            syncState.newestKnownPublishedAt = newest
        }
        if let oldest = posts.map(\.publishedAt).min() {
            syncState.oldestKnownPublishedAt = oldest
        }
    }

    static func applyDetail(_ detail: KemonoPostDetail, to post: Post) {
        post.title = detail.title
        post.publishedAt = detail.publishedAt
        post.contentHTML = detail.contentHTML
        post.isRead = true
        post.lastOpenedAt = .now

        if let firstPath = detail.mediaItems.first?.path {
            post.previewURL = KemonoURLResolver.previewURL(for: firstPath)
        }
    }

    static func recordRecentView(for post: Post, in context: ModelContext) {
        let key = post.key
        let descriptor = FetchDescriptor<RecentPost>(
            predicate: #Predicate { $0.postKey == key }
        )

        if let existing = try? context.fetch(descriptor).first {
            existing.lastViewedAt = .now
            existing.post = post
        } else {
            context.insert(RecentPost(post: post))
        }

        trimRecentPosts(in: context)
    }

    static func fetchRecentPosts(in context: ModelContext, limit: Int = 100) throws -> [Post] {
        var descriptor = FetchDescriptor<RecentPost>(
            sortBy: [SortDescriptor(\RecentPost.lastViewedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return try context.fetch(descriptor).compactMap(\.post)
    }

    private static func trimRecentPosts(in context: ModelContext) {
        var descriptor = FetchDescriptor<RecentPost>(
            sortBy: [SortDescriptor(\RecentPost.lastViewedAt, order: .reverse)]
        )
        descriptor.fetchOffset = AuthorRepository.maxRecentPosts

        guard let stale = try? context.fetch(descriptor) else { return }
        for entry in stale {
            context.delete(entry)
        }
    }
}
