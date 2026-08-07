import Foundation
import SwiftData

/// Orchestrates author post loading and incremental sync.
@MainActor
final class SyncEngine {
    private let modelContext: ModelContext
    private let apiClient: KemonoAPIClient

    init(modelContext: ModelContext, apiClient: KemonoAPIClient? = nil) {
        self.modelContext = modelContext
        self.apiClient = apiClient ?? KemonoAPIClient()
    }

    func refreshSubscriptions() async {
        // TODO: iterate subscribed authors and sync each one incrementally.
    }

    /// Loads all posts for an author from the API and stores them locally (Qt path).
    func loadAuthorPosts(_ author: Author) async throws -> Int {
        try await refreshArtistInfo(author)

        let results = try await apiClient.fetchAllArtistPosts(
            service: author.service,
            authorId: author.authorId
        )

        let chunkSize = 75
        var imported = 0
        for chunkStart in stride(from: 0, to: results.count, by: chunkSize) {
            let chunkEnd = min(chunkStart + chunkSize, results.count)
            let chunk = Array(results[chunkStart..<chunkEnd])
            imported += PostRepository.upsertBatch(
                from: chunk,
                author: author,
                in: modelContext
            )
            try modelContext.save()
            await Task.yield()
        }

        PostRepository.updateSyncState(
            for: author,
            posts: results,
            isFullySynced: true,
            in: modelContext
        )

        try modelContext.save()
        return imported
    }

    func syncAuthor(_ author: Author) async {
        do {
            _ = try await loadAuthorPosts(author)
        } catch {
            // Caller handles errors via thrown value from loadAuthorPosts.
        }
    }

    private func refreshArtistInfo(_ author: Author) async throws {
        do {
            let info = try await apiClient.fetchArtistInfo(
                service: author.service,
                authorId: author.authorId
            )
            author.apply(info)
        } catch {
            // Catalog data is enough to show the page; profile refresh is best-effort.
        }
    }
}
