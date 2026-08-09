import Foundation

enum PostFeedAggregatorError: Error, LocalizedError, Sendable {
    case allServersFailed

    var errorDescription: String? {
        switch self {
        case .allServersFailed:
            return "Couldn't load posts from any server."
        }
    }
}

/// Fans a paginated post query out across multiple servers and merges the results
/// (round-robin interleave in server order) with cross-server dedup by `globalID`.
@MainActor
final class PostFeedAggregator {
    typealias Client = any BooruSite & BooruBrowsing
    typealias Fetch = @Sendable (Client, Int, Int) async throws -> [BooruPost]

    private struct Cursor {
        let client: Client
        var nextPage: Int
        var hasMore: Bool
    }

    private var cursors: [Cursor]
    private var seen: Set<String> = []
    private let perServerLimit: Int

    init(clients: [Client], perServerLimit: Int = 40) {
        self.perServerLimit = perServerLimit
        cursors = clients.map { Cursor(client: $0, nextPage: 1, hasMore: true) }
    }

    var hasMore: Bool {
        cursors.contains(where: \.hasMore)
    }

    /// Fetches the next page from every server that still has more results, then interleaves + dedups.
    /// Throws ``PostFeedAggregatorError/allServersFailed`` when every active server errors
    /// (distinct from a successful empty page).
    func loadNextPage(fetch: @escaping Fetch) async throws -> [BooruPost] {
        let active = cursors.enumerated().filter { $0.element.hasMore }
        guard !active.isEmpty else { return [] }

        let limit = perServerLimit
        // A `nil` result means that server failed (e.g. auth/network); it is dropped from this
        // page and retired for the session so one bad server can't break the whole feed.
        var fetched: [Int: [BooruPost]] = [:]
        var failureCount = 0

        try await withThrowingTaskGroup(of: (Int, [BooruPost]?).self) { group in
            for (index, cursor) in active {
                let client = cursor.client
                let page = cursor.nextPage
                group.addTask {
                    do {
                        return (index, try await fetch(client, page, limit))
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let urlError as URLError where urlError.code == .cancelled {
                        throw CancellationError()
                    } catch {
                        return (index, nil)
                    }
                }
            }
            for try await (index, posts) in group {
                if let posts {
                    fetched[index] = posts
                } else {
                    failureCount += 1
                }
            }
        }

        for (index, _) in active {
            if let count = fetched[index]?.count {
                cursors[index].nextPage += 1
                cursors[index].hasMore = count >= limit
            } else {
                cursors[index].hasMore = false
            }
        }

        if fetched.isEmpty, failureCount > 0 {
            throw PostFeedAggregatorError.allServersFailed
        }

        // Round-robin interleave, preserving original server order.
        let orderedIndices = active.map(\.offset)
        var merged: [BooruPost] = []
        var row = 0
        var addedSomething = true
        while addedSomething {
            addedSomething = false
            for index in orderedIndices {
                guard let posts = fetched[index], row < posts.count else { continue }
                addedSomething = true
                let post = posts[row]
                if seen.insert(post.globalID).inserted {
                    merged.append(post)
                }
            }
            row += 1
        }
        return merged
    }
}
