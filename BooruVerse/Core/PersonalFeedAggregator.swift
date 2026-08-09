import Foundation

/// Fans paginated tag-set queries across multiple servers, then merges by `globalID`
/// and sorts by publication time (newest first).
@MainActor
final class PersonalFeedAggregator {
    typealias Client = any BooruSite & BooruBrowsing

    private struct SetCursor {
        let tags: String
        let aggregator: PostFeedAggregator
    }

    private var setCursors: [SetCursor]
    private var seen: Set<String> = []
    private let clients: [Client]
    private let perServerLimit: Int

    init(
        tagSets: [[String]],
        clients: [Client],
        perServerLimit: Int = 40
    ) {
        self.clients = clients
        self.perServerLimit = perServerLimit
        setCursors = tagSets.compactMap { tags in
            let query = tags.joined(separator: " ")
            guard !query.isEmpty else { return nil }
            return SetCursor(
                tags: query,
                aggregator: PostFeedAggregator(clients: clients, perServerLimit: perServerLimit)
            )
        }
    }

    var hasMore: Bool {
        setCursors.contains { $0.aggregator.hasMore }
    }

    /// Fetches the next page for every tag set that still has results, dedupes, and sorts by date.
    func loadNextPage(
        ratingFilter: RatingFilter,
        queryBuilder: @escaping @Sendable (String, RatingFilter, BooruAPIFlavor) -> String
    ) async throws -> [BooruPost] {
        let active = setCursors.filter { $0.aggregator.hasMore }
        guard !active.isEmpty else { return [] }

        var batches: [[BooruPost]] = []
        var failureCount = 0
        var successCount = 0

        // Caps how many tag-set pages run at once (each set still fans out across servers).
        let maxConcurrentSets = 3

        try await withThrowingTaskGroup(of: Result<[BooruPost], Error>.self) { group in
            var iterator = active.makeIterator()
            var inFlight = 0

            func enqueueNext() {
                guard inFlight < maxConcurrentSets, let cursor = iterator.next() else { return }
                inFlight += 1
                let tags = cursor.tags
                let aggregator = cursor.aggregator
                // Network work runs in the child task; aggregator state updates stay on MainActor
                // via the awaited loadNextPage call.
                // Cap concurrent sets; each set's per-server fetches still run in
                // PostFeedAggregator's inner task group (not serialized on MainActor).
                group.addTask { @MainActor in
                    do {
                        let posts = try await aggregator.loadNextPage { client, page, limit in
                            let query = queryBuilder(tags, ratingFilter, client.apiFlavor)
                            return try await client.fetchPosts(tags: query, page: page, limit: limit)
                        }
                        return .success(posts)
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let urlError as URLError where urlError.code == .cancelled {
                        throw CancellationError()
                    } catch {
                        return .failure(error)
                    }
                }
            }

            for _ in 0..<min(maxConcurrentSets, active.count) {
                enqueueNext()
            }

            while inFlight > 0 {
                let result = try await group.next()!
                    inFlight -= 1
                switch result {
                case .success(let batch):
                    successCount += 1
                    batches.append(batch)
                case .failure(let error):
                    if error is PostFeedAggregatorError {
                        failureCount += 1
                    } else {
                        failureCount += 1
                    }
                }
                enqueueNext()
            }
        }

        if successCount == 0, failureCount > 0 {
            throw PostFeedAggregatorError.allServersFailed
        }

        var merged: [BooruPost] = []
        for batch in batches {
            for post in batch where seen.insert(post.globalID).inserted {
                merged.append(post)
            }
        }

        // Sort off the hot path of UI updates.
        let sorted = await Task.detached(priority: .utility) {
            merged.sorted(by: PersonalFeedAggregator.recencySort)
        }.value
        return sorted
    }

    /// Newest first. Missing dates sort after dated posts but keep stable relative order via globalID.
    nonisolated static func recencySort(_ lhs: BooruPost, _ rhs: BooruPost) -> Bool {
        switch (lhs.createdAt, rhs.createdAt) {
        case let (l?, r?):
            if l != r { return l > r }
            return lhs.globalID > rhs.globalID
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        case (nil, nil):
            return lhs.globalID > rhs.globalID
        }
    }
}
