import Foundation

@MainActor
@Observable
final class PoolsViewModel {
    static let previewCount = 8

    let servers: [any BooruSite & BooruBrowsing]

    var pools: [BooruPool] = []
    var searchText = ""
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?

    /// Cached preview thumbnail URLs for the first posts of each pool, keyed by pool globalID.
    private(set) var previews: [String: [URL]] = [:]
    private var previewsInFlight: Set<String> = []

    private struct Cursor {
        let server: any BooruSite & BooruBrowsing
        let pools: BooruPools
        var nextPage: Int
        var hasMore: Bool
    }

    private var cursors: [Cursor] = []
    private var activeQuery = ""
    private var loadGeneration = 0
    private var hasBootstrapped = false
    private var loadedPoolIDs: Set<String> = []

    private var poolServers: [(server: any BooruSite & BooruBrowsing, pools: BooruPools)] {
        servers.compactMap { server in
            (server as? BooruPools).map { (server, $0) }
        }
    }

    private var hasMorePages: Bool {
        cursors.contains(where: \.hasMore)
    }

    init(servers: [any BooruSite & BooruBrowsing]) {
        self.servers = servers
    }

    func site(for pool: BooruPool) -> (any BooruSite & BooruBrowsing)? {
        servers.first { $0.siteID == pool.serverID }
    }

    func bootstrapIfNeeded() async {
        // Only mark bootstrapped after a completed (non-cancelled) load. Otherwise leaving the
        // tab mid-fetch permanently stuck the UI on "No Pools".
        if hasBootstrapped {
            if pools.isEmpty, !isLoading, !isLoadingMore {
                await reload(clearVisiblePools: true)
            }
            return
        }
        await reload(clearVisiblePools: true)
        guard !Task.isCancelled else { return }
        hasBootstrapped = true
    }

    func refresh() async {
        await reload(clearVisiblePools: false)
    }

    func search() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != activeQuery else { return }
        await reload(clearVisiblePools: true)
    }

    func loadMoreIfNeeded(currentPool pool: BooruPool) async {
        guard let index = pools.firstIndex(where: { $0.globalID == pool.globalID }) else { return }
        guard index >= pools.count - 4 else { return }
        await loadMore()
    }

    func previewURLs(for pool: BooruPool) -> [URL] {
        previews[pool.globalID] ?? []
    }

    func loadPreviews(for pool: BooruPool) async {
        let id = pool.globalID
        if let existing = previews[id], !existing.isEmpty { return }
        guard !previewsInFlight.contains(id),
              let poolSite = site(for: pool) as? BooruPools else { return }

        previewsInFlight.insert(id)
        defer { previewsInFlight.remove(id) }

        do {
            let posts = try await poolSite.fetchPoolPosts(poolID: pool.id, page: 1, limit: Self.previewCount)
            guard !Task.isCancelled else { return }
            previews[id] = posts.prefix(Self.previewCount).compactMap(\.previewURL)
        } catch is CancellationError {
            // Leave cache unset so a later .task retry can load.
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            guard !Task.isCancelled else { return }
            // Mark as attempted-empty so we don't hammer a failing endpoint every appear.
            if previews[id] == nil {
                previews[id] = []
            }
        }
    }

    /// - Parameter clearVisiblePools: When true (first load / new search), show a loading state.
    ///   When false (pull-to-refresh), keep the current list until new data arrives so a cancelled
    ///   refresh cannot wipe the screen into "No Pools".
    private func reload(clearVisiblePools: Bool) async {
        loadGeneration += 1
        let generation = loadGeneration

        activeQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        loadedPoolIDs = []
        errorMessage = nil
        cursors = poolServers.map { Cursor(server: $0.server, pools: $0.pools, nextPage: 1, hasMore: true) }
        previewsInFlight = []

        if clearVisiblePools {
            pools = []
            previews = [:]
            isLoading = true
        } else if pools.isEmpty {
            isLoading = true
        }

        defer {
            if generation == loadGeneration {
                isLoading = false
                isLoadingMore = false
            }
        }

        await fetchPage(generation: generation, isInitial: true)

        if Task.isCancelled, generation == loadGeneration, pools.isEmpty {
            // Cancelled before any data — allow bootstrap/retry paths to run again.
            hasBootstrapped = false
        }
    }

    private func loadMore() async {
        guard hasMorePages, !isLoading, !isLoadingMore else { return }
        let generation = loadGeneration
        isLoadingMore = true
        defer { if generation == loadGeneration { isLoadingMore = false } }
        await fetchPage(generation: generation, isInitial: false)
    }

    private func fetchPage(generation: Int, isInitial: Bool) async {
        let active = cursors.enumerated().filter { $0.element.hasMore }
        guard !active.isEmpty else { return }

        let query = activeQuery
        var fetched: [Int: [BooruPool]] = [:]
        var failures = 0

        await withTaskGroup(of: (Int, Result<[BooruPool], Error>).self) { group in
            for (index, cursor) in active {
                let poolsAPI = cursor.pools
                let page = cursor.nextPage
                group.addTask {
                    do {
                        let result = try await poolsAPI.fetchPools(query: query, page: page)
                        return (index, .success(result))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            for await (index, result) in group {
                switch result {
                case .success(let pools):
                    fetched[index] = pools
                case .failure(let error):
                    if error is CancellationError { return }
                    if let urlError = error as? URLError, urlError.code == .cancelled { return }
                    failures += 1
                    fetched[index] = []
                }
            }
        }

        guard generation == loadGeneration, !Task.isCancelled else { return }

        for (index, _) in active {
            let result = fetched[index] ?? []
            cursors[index].nextPage += 1
            cursors[index].hasMore = !result.isEmpty
        }

        let orderedIndices = active.map(\.offset)
        var merged: [BooruPool] = []
        var row = 0
        var added = true
        while added {
            added = false
            for index in orderedIndices {
                guard let result = fetched[index], row < result.count else { continue }
                added = true
                let pool = result[row]
                if loadedPoolIDs.insert(pool.globalID).inserted {
                    merged.append(pool)
                }
            }
            row += 1
        }

        if isInitial {
            // Keep existing rows if a refresh produced nothing due to total failure.
            if merged.isEmpty, !pools.isEmpty, failures == active.count {
                errorMessage = "Couldn't refresh pools."
                return
            }
            pools = merged
            let liveIDs = Set(merged.map(\.globalID))
            previews = previews.filter { liveIDs.contains($0.key) }
            if merged.isEmpty, failures > 0 {
                errorMessage = "Couldn't load pools."
            }
        } else {
            pools.append(contentsOf: merged)
        }
    }
}
