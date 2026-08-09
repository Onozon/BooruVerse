import Foundation

enum PostListMode: Sendable {
    case browse
    case favorites
    case pool
    case popular
}

@MainActor
@Observable
final class BrowseViewModel {
    static let pageSize = 40
    static let perServerLimit = 40

    /// Backends this view model aggregates. One element for pool/single-server modes, many for browse.
    let servers: [any BooruSite & BooruBrowsing]
    let mode: PostListMode

    /// Pool identifier when `mode == .pool`.
    let poolID: Int?

    /// Selected period when `mode == .popular` and channel is a popular window.
    private(set) var popularPeriod: PopularPeriod = .day
    /// Feed capsule selection (Personal / Day / Week / Month). Used when `mode == .popular`.
    private(set) var feedChannel: FeedChannel = .day

    var tagQuery = TagQuery()
    /// Everything fetched from the servers, before the rating filter is applied.
    private(set) var allPosts: [BooruPost] = []
    /// Posts actually shown, honoring the global rating filter. Recomputes when the setting changes.
    var posts: [BooruPost] {
        let filter = AppSettingsStore.shared.ratingFilter
        guard filter != .all else { return allPosts }
        return allPosts.filter { filter.allows($0.rating) }
    }
    /// Tag sidebar state — separate observable so resolve/refresh does not redraw the grid.
    @ObservationIgnored
    let tagChrome = PageTagChrome()

    var suggestions: [BooruTag] = []
    var inputFragment = ""

    private(set) var visiblePage = 1
    private(set) var loadedThroughPage = 0
    private(set) var hasMorePages = true
    private(set) var isLoadingMore = false

    var isLoading = false
    var isSearchingSuggestions = false
    var errorMessage: String?

    private var postsLoadGeneration = 0
    private(set) var listGeneration = 0

    private(set) var favoritesRevision = 0

    // Compatibility shims for call sites that still read tag chrome via the VM.
    var pageTags: [BooruTag] {
        get { tagChrome.pageTags }
        set { tagChrome.replacePageTags(newValue) }
    }
    var pageTagGroups: [BooruTagGroup] { tagChrome.pageTagGroups }
    var tagIndexRevision: Int { tagChrome.tagIndexRevision }
    var pageTagsRevision: Int { tagChrome.pageTagsRevision }
    var isResolvingPageTagColors: Bool { tagChrome.isResolvingPageTagColors }

    private var hasBootstrapped = false
    private var loadedPostIDs: Set<String> = []

    /// Browse pagination fan-out.
    private var browseAggregator: PostFeedAggregator?
    /// Personal feed: one multi-server cursor per selected tag set.
    private var personalAggregator: PersonalFeedAggregator?
    /// Interleaved (server, native id) favorite targets for favorites mode.
    private var favoritePairs: [(server: any BooruSite & BooruBrowsing, id: Int)] = []

    private var suggestionTask: Task<Void, Never>?
    private var pageTagsResolveTask: Task<Void, Never>?
    private var pageTagsRefreshTask: Task<Void, Never>?

    /// Tag name -> occurrence count for the current page. Cached so incremental type-resolution
    /// refreshes only re-look-up colors instead of re-scanning every post on the page.
    private var pageTagCounts: [(name: String, count: Int)] = []
    /// Timestamp of the last applied page-tag refresh, used to throttle rebuilds during resolution.
    private var lastPageTagsRefresh: Date = .distantPast

    var displayName: String {
        switch servers.count {
        case 0: "No Servers"
        case 1: servers[0].displayName
        default: "All Servers"
        }
    }

    init(servers: [any BooruSite & BooruBrowsing], mode: PostListMode = .browse, poolID: Int? = nil) {
        self.servers = servers
        self.mode = mode
        self.poolID = poolID
    }

    convenience init(site: any BooruSite & BooruBrowsing, mode: PostListMode = .browse, poolID: Int? = nil) {
        self.init(servers: [site], mode: mode, poolID: poolID)
    }

    func loadTagCache() {
        for server in servers {
            TagIndexStore.shared.loadCache(siteID: server.siteID)
        }
        tagChrome.bumpTagIndexRevision()
    }

    /// Loads data once per view-model lifetime. Safe to call from `.task` on tab switches.
    func bootstrapIfNeeded() async {
        loadTagCache()
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        switch mode {
        case .browse, .pool, .popular:
            await loadPosts(resetPage: true)
        case .favorites:
            await loadFavorites()
        }
    }

    func postTagGroups(for post: BooruPost) -> [BooruTagGroup] {
        _ = tagChrome.tagIndexRevision
        let tags = post.tags.map { name in
            BooruTag(
                name: name,
                postCount: 1,
                type: TagIndexStore.shared.type(for: name, siteID: post.serverID) ?? tagType(for: name)
            )
        }
        return tags.groupedByType
    }

    func resolvePostTags(for post: BooruPost) {
        let server = servers.first { $0.siteID == post.serverID }
        resolveTagNames(post.tags, on: server)
    }

    func resolveTagNames(_ names: [String]) {
        for server in servers {
            resolveTagNames(names, on: server)
        }
    }

    private func resolveTagNames(_ names: [String], on server: (any BooruSite & BooruBrowsing)?) {
        guard let server, !names.isEmpty else { return }
        Task {
            await TagIndexStore.shared.resolveMissing(
                names: names,
                site: server,
                siteID: server.siteID
            ) {
                self.tagChrome.bumpTagIndexRevision()
            }
        }
    }

    /// Best-known type for a tag across all enabled servers, preferring a specific (non-general) type.
    func tagType(for name: String) -> BooruTagType {
        _ = tagChrome.tagIndexRevision
        for server in servers {
            if let type = TagIndexStore.shared.type(for: name, siteID: server.siteID), type != .general {
                return type
            }
        }
        for server in servers {
            if let type = TagIndexStore.shared.type(for: name, siteID: server.siteID) {
                return type
            }
        }
        return .general
    }

    func isFavorite(_ post: BooruPost) -> Bool {
        _ = favoritesRevision
        return FavoritePostStore.shared.isFavorite(postID: post.id, siteID: post.serverID)
    }

    func toggleFavorite(_ post: BooruPost) {
        FavoritePostStore.shared.toggle(postID: post.id, siteID: post.serverID)
        favoritesRevision += 1
        if mode == .favorites {
            Task { await refreshPosts() }
        }
    }

    func pageNumber(forPostAt index: Int) -> Int {
        guard index >= 0 else { return 1 }
        return index / Self.pageSize + 1
    }

    func setVisiblePage(_ page: Int) {
        guard page > 0, page != visiblePage else { return }
        visiblePage = page
        updatePageTagsForVisiblePage()
    }

    func loadMorePosts() async {
        guard hasMorePages, !isLoading, !isLoadingMore else { return }

        switch mode {
        case .browse:
            await fetchBrowsePage(append: true)
        case .favorites:
            await fetchFavoritesPage(append: true)
        case .pool:
            await fetchPoolPage(append: true)
        case .popular:
            if feedChannel == .personal {
                await fetchPersonalPage(append: true)
            } else {
                await fetchPopularPage(append: true)
            }
        }
    }

    func setPopularPeriod(_ period: PopularPeriod) async {
        await setFeedChannel(FeedChannel(period: period))
    }

    /// Sets channel without reloading (used when restoring a persisted session).
    func applyFeedChannel(_ channel: FeedChannel) {
        feedChannel = channel
        if let period = channel.popularPeriod {
            popularPeriod = period
        }
    }

    func setFeedChannel(_ channel: FeedChannel) async {
        guard mode == .popular, channel != feedChannel else { return }
        applyFeedChannel(channel)
        await resetAndLoadFirstPage()
    }

    /// Reload Personal when the selected tag sets change.
    func reloadPersonalFeedIfNeeded() async {
        guard mode == .popular, feedChannel == .personal else { return }
        await resetAndLoadFirstPage()
    }

    func loadMorePostsIfNeeded(nearPostID globalID: String) async {
        guard let index = posts.firstIndex(where: { $0.globalID == globalID }) else { return }
        guard index >= posts.count - 8 else { return }
        await loadMorePosts()
    }

    func loadFavorites() async {
        guard mode == .favorites else { return }
        rebuildFavoritePairs()
        await resetAndLoadFirstPage()
    }

    func savePostToPhotos(_ post: BooruPost) async throws {
        try await PostImageSaver.saveToPhotos(post: post)
    }

    func exportDocument(for post: BooruPost) async throws -> SavedImageDocument {
        let data = try await PostImageSaver.imageData(for: post)
        return SavedImageDocument(data: data)
    }

    func refreshPosts() async {
        if mode == .favorites {
            rebuildFavoritePairs()
            await resetAndLoadFirstPage()
        } else {
            await loadPosts(resetPage: true)
        }
    }

    func loadPosts(resetPage: Bool = false) async {
        if mode == .favorites {
            if resetPage {
                rebuildFavoritePairs()
                await resetAndLoadFirstPage()
            } else {
                await loadMorePosts()
            }
            return
        }

        if resetPage {
            await resetAndLoadFirstPage()
        } else {
            await loadMorePosts()
        }
    }

    private func resetAndLoadFirstPage() async {
        postsLoadGeneration += 1
        listGeneration += 1
        loadedThroughPage = 0
        hasMorePages = true
        visiblePage = 1
        allPosts = []
        loadedPostIDs = []
        pageTagsResolveTask?.cancel()
        errorMessage = nil

        switch mode {
        case .browse:
            browseAggregator = PostFeedAggregator(clients: servers, perServerLimit: Self.perServerLimit)
            await fetchBrowsePage(append: false)
        case .favorites:
            await fetchFavoritesPage(append: false)
        case .pool:
            await fetchPoolPage(append: false)
        case .popular:
            if feedChannel == .personal {
                let tagSets = PersonalFeedStore.shared.personalSets.map(\.tags)
                if tagSets.isEmpty {
                    personalAggregator = nil
                    allPosts = []
                    loadedPostIDs = []
                    hasMorePages = false
                    updatePageTagsForVisiblePage()
                    return
                }
                personalAggregator = PersonalFeedAggregator(
                    tagSets: tagSets,
                    clients: servers,
                    perServerLimit: Self.perServerLimit
                )
                await fetchPersonalPage(append: false)
            } else {
                personalAggregator = nil
                await fetchPopularPage(append: false)
            }
        }
        updatePageTagsForVisiblePage()
    }

    private func fetchBrowsePage(append: Bool) async {
        guard let aggregator = browseAggregator else { return }
        guard aggregator.hasMore else {
            hasMorePages = false
            return
        }

        let generation = postsLoadGeneration
        let isInitial = !append && posts.isEmpty
        setLoading(isInitial: isInitial, true)
        defer { setLoading(isInitial: isInitial, false) }

        let query = tagQuery.searchString
        let ratingFilter = AppSettingsStore.shared.ratingFilter
        do {
            let fetched = try await aggregator.loadNextPage { client, page, limit in
                let tags = Self.query(query, withRating: ratingFilter, flavor: client.apiFlavor)
                return try await client.fetchPosts(tags: tags, page: page, limit: limit)
            }
            guard generation == postsLoadGeneration else { return }
            appendPosts(fetched, isInitial: isInitial)
            loadedThroughPage += 1
            hasMorePages = aggregator.hasMore
            await fillFilteredPostsIfNeeded()
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            handleFetchError(error, generation: generation, isInitial: isInitial)
        }
    }

    private func fetchPoolPage(append: Bool) async {
        guard hasMorePages, let poolID, let poolSite = servers.first as? BooruPools else {
            hasMorePages = false
            return
        }

        let generation = postsLoadGeneration
        let pageToLoad = loadedThroughPage + 1
        let isInitial = !append && posts.isEmpty
        setLoading(isInitial: isInitial, true)
        defer { setLoading(isInitial: isInitial, false) }

        do {
            let fetched = try await poolSite.fetchPoolPosts(
                poolID: poolID,
                page: pageToLoad,
                limit: Self.pageSize
            )
            guard generation == postsLoadGeneration else { return }
            appendPosts(fetched, isInitial: isInitial)
            loadedThroughPage = pageToLoad
            hasMorePages = !fetched.isEmpty
            await fillFilteredPostsIfNeeded()
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            handleFetchError(error, generation: generation, isInitial: isInitial)
        }
    }

    private func fetchPopularPage(append: Bool) async {
        // popular endpoints return a single fixed list; there is no pagination.
        guard !append else { return }

        let popularServers = servers.compactMap { $0 as? BooruPopular }
        guard !popularServers.isEmpty else {
            hasMorePages = false
            allPosts = []
            loadedPostIDs = []
            return
        }

        let generation = postsLoadGeneration
        let period = popularPeriod
        isLoading = true
        defer { isLoading = false }

        do {
            var byServer: [Int: [BooruPost]] = [:]
            var failureCount = 0
            try await withThrowingTaskGroup(of: (Int, [BooruPost]?).self) { group in
                for (index, server) in popularServers.enumerated() {
                    group.addTask {
                        do {
                            return (index, try await server.fetchPopular(period: period))
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
                        byServer[index] = posts
                    } else {
                        failureCount += 1
                    }
                }
            }
            guard generation == postsLoadGeneration else { return }

            if byServer.isEmpty, failureCount > 0 {
                throw PostFeedAggregatorError.allServersFailed
            }

            let merged = Self.interleave(byServer, order: Array(popularServers.indices))
            appendPosts(merged, isInitial: true)
            loadedThroughPage = 1
            hasMorePages = false
            await fillFilteredPostsIfNeeded()
        } catch is CancellationError {
            return
        } catch {
            handleFetchError(error, generation: generation, isInitial: true)
        }
    }

    private func fetchPersonalPage(append: Bool) async {
        guard let aggregator = personalAggregator else {
            hasMorePages = false
            return
        }
        guard aggregator.hasMore else {
            hasMorePages = false
            return
        }

        let generation = postsLoadGeneration
        let isInitial = !append && posts.isEmpty
        setLoading(isInitial: isInitial, true)
        defer { setLoading(isInitial: isInitial, false) }

        let ratingFilter = AppSettingsStore.shared.ratingFilter
        do {
            let fetched = try await aggregator.loadNextPage(ratingFilter: ratingFilter) { base, filter, flavor in
                Self.query(base, withRating: filter, flavor: flavor)
            }
            guard generation == postsLoadGeneration else { return }
            appendPosts(fetched, isInitial: isInitial, resortByDate: true)
            loadedThroughPage += 1
            hasMorePages = aggregator.hasMore
            await fillFilteredPostsIfNeeded()
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch {
            handleFetchError(error, generation: generation, isInitial: isInitial)
        }
    }

    private func fetchFavoritesPage(append: Bool) async {
        guard hasMorePages else { return }

        let generation = postsLoadGeneration
        let pageToLoad = loadedThroughPage + 1
        let isInitial = !append && posts.isEmpty
        setLoading(isInitial: isInitial, true)
        defer { setLoading(isInitial: isInitial, false) }

        let start = (pageToLoad - 1) * Self.pageSize
        guard start < favoritePairs.count else {
            hasMorePages = false
            return
        }

        let slice = Array(favoritePairs[start..<min(start + Self.pageSize, favoritePairs.count)])
        let order = Dictionary(
            uniqueKeysWithValues: slice.enumerated().map { ("\($0.element.server.siteID)#\($0.element.id)", $0.offset) }
        )

        var fetched: [BooruPost] = []
        // Cap concurrency at 6 parallel requests per chunk. Individual failures are dropped
        // (via `try?`) so a single bad server doesn't blank the favorites page.
        for chunkStart in stride(from: 0, to: slice.count, by: 6) {
            let chunk = Array(slice[chunkStart..<min(chunkStart + 6, slice.count)])
            let batch = await withTaskGroup(of: BooruPost?.self) { group in
                for target in chunk {
                    group.addTask {
                        try? await target.server.fetchPost(id: target.id)
                    }
                }
                return await group.reduce(into: [BooruPost]()) { partial, post in
                    if let post { partial.append(post) }
                }
            }
            fetched.append(contentsOf: batch)
        }

        guard generation == postsLoadGeneration else { return }

        fetched.sort { (order[$0.globalID] ?? 0) < (order[$1.globalID] ?? 0) }
        appendPosts(fetched, isInitial: isInitial)

        loadedThroughPage = pageToLoad
        hasMorePages = start + Self.pageSize < favoritePairs.count
    }

    private func rebuildFavoritePairs() {
        let perServer = servers.map { server in
            (server, FavoritePostStore.shared.favoriteIDs(for: server.siteID))
        }
        var pairs: [(server: any BooruSite & BooruBrowsing, id: Int)] = []
        var row = 0
        var added = true
        while added {
            added = false
            for (server, ids) in perServer where row < ids.count {
                pairs.append((server, ids[row]))
                added = true
            }
            row += 1
        }
        favoritePairs = pairs
    }

    private func appendPosts(_ fetched: [BooruPost], isInitial: Bool, resortByDate: Bool = false) {
        if isInitial {
            allPosts = fetched
            loadedPostIDs = Set(fetched.map(\.globalID))
        } else {
            let unique = fetched.filter { loadedPostIDs.insert($0.globalID).inserted }
            allPosts.append(contentsOf: unique)
        }
        if resortByDate {
            allPosts.sort(by: PersonalFeedAggregator.recencySort)
        }
    }

    private func setLoading(isInitial: Bool, _ isOn: Bool) {
        if isInitial {
            isLoading = isOn
        } else {
            isLoadingMore = isOn
        }
    }

    private func handleFetchError(_ error: Error, generation: Int, isInitial: Bool) {
        guard generation == postsLoadGeneration else { return }
        if isInitial {
            errorMessage = error.localizedDescription
            allPosts = []
            loadedPostIDs = []
            tagChrome.clear()
            pageTagsResolveTask?.cancel()
        }
    }

    /// Appends the flavor-specific rating constraint to a browse query. Server-side filtering is a
    /// bandwidth optimization; `posts` still applies the same filter client-side as a safety net.
    nonisolated static func query(_ base: String, withRating filter: RatingFilter, flavor: BooruAPIFlavor) -> String {
        guard let ratingTag = ratingTag(for: filter, flavor: flavor) else { return base }
        return base.isEmpty ? ratingTag : "\(base) \(ratingTag)"
    }

    nonisolated private static func ratingTag(for filter: RatingFilter, flavor: BooruAPIFlavor) -> String? {
        switch filter {
        case .all:
            return nil
        case .hideExplicit:
            switch flavor {
            case .moebooru: return "-rating:e"          // Moebooru honors only one rating tag.
            case .gelbooru: return "-rating:explicit"
            case .danbooru2: return "rating:g,s,q"      // comma-OR keeps it to a single tag.
            }
        case .safeOnly:
            switch flavor {
            case .moebooru: return "rating:s"           // positive form (double-negation is ignored).
            case .gelbooru: return "-rating:questionable -rating:explicit"
            case .danbooru2: return "rating:g"          // exclude Danbooru sensitive (`s`).
            }
        }
    }

    /// Reload when the global rating filter changes (server query + client filter must stay in sync).
    func applyRatingFilterChange() async {
        await loadPosts(resetPage: true)
    }

    /// When the client filter empties the visible list but more pages exist, keep paging.
    func fillFilteredPostsIfNeeded() async {
        var guardCount = 0
        while posts.isEmpty, hasMorePages, !isLoading, !isLoadingMore, guardCount < 8 {
            guardCount += 1
            await loadMorePosts()
        }
    }

    private static func interleave(_ groups: [Int: [BooruPost]], order: [Int]) -> [BooruPost] {
        var result: [BooruPost] = []
        var seen = Set<String>()
        var row = 0
        var added = true
        while added {
            added = false
            for index in order {
                guard let posts = groups[index], row < posts.count else { continue }
                added = true
                let post = posts[row]
                if seen.insert(post.globalID).inserted {
                    result.append(post)
                }
            }
            row += 1
        }
        return result
    }

    func addTag(_ tag: String) async {
        guard mode == .browse else { return }
        tagQuery.add(tag)
        inputFragment = ""
        suggestions = []
        await loadPosts(resetPage: true)
    }

    func removeTag(_ tag: String) async {
        guard mode == .browse else { return }
        tagQuery.remove(tag)
        await loadPosts(resetPage: true)
    }

    func clearTags() async {
        guard mode == .browse else { return }
        tagQuery.clear()
        inputFragment = ""
        suggestions = []
        await loadPosts(resetPage: true)
    }

    var savedTagSets: [SavedTagSet] {
        _ = SavedTagSetStore.shared.revision
        return SavedTagSetStore.shared.sets
    }

    func saveCurrentTagSet(named name: String, addToPersonal: Bool = false) {
        guard !tagQuery.tags.isEmpty else { return }
        SavedTagSetStore.shared.save(name: name, tags: tagQuery.tags, addToPersonal: addToPersonal)
        AppDebug.log(
            "SavedTagSets",
            "save requested name=\(name) tags=\(tagQuery.tags.count) personal=\(addToPersonal)"
        )
    }

    func applySavedTagSet(_ set: SavedTagSet) async {
        guard mode == .browse else { return }
        tagQuery.tags = set.tags
        inputFragment = ""
        suggestions = []
        await loadPosts(resetPage: true)
    }

    func deleteSavedTagSet(_ set: SavedTagSet) {
        SavedTagSetStore.shared.delete(set)
    }

    func onInputChanged(_ value: String) {
        suggestionTask?.cancel()

        let fragment = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard fragment.count >= 2 else {
            suggestions = []
            return
        }

        suggestionTask = Task {
            isSearchingSuggestions = true
            defer { isSearchingSuggestions = false }

            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }

            let merged = await suggestFromAllServers(fragment: fragment)
            guard !Task.isCancelled else { return }
            suggestions = merged
        }
    }

    private func suggestFromAllServers(fragment: String) async -> [BooruTag] {
        let current = tagQuery.tags
        let lists = await withTaskGroup(of: [BooruTag].self) { group -> [[BooruTag]] in
            for server in servers {
                group.addTask {
                    (try? await server.suggestTags(currentTags: current, fragment: fragment, limit: 24)) ?? []
                }
            }
            return await group.reduce(into: [[BooruTag]]()) { $0.append($1) }
        }

        var byName: [String: BooruTag] = [:]
        for list in lists {
            for tag in list where !tag.name.isEmpty {
                if let existing = byName[tag.name] {
                    byName[tag.name] = BooruTag(
                        name: tag.name,
                        postCount: existing.postCount + tag.postCount,
                        type: existing.type != .general ? existing.type : tag.type
                    )
                } else {
                    byName[tag.name] = tag
                }
            }
        }

        let results = byName.values
            .filter { !current.contains($0.name) }
            .sorted { $0.postCount > $1.postCount }
        return Array(results.prefix(24))
    }

    func commitInput() async {
        let fragment = inputFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fragment.isEmpty else { return }
        await addTag(fragment)
    }

    /// Cheap rebuild used by incremental resolution: re-colors the cached page tags from the
    /// latest resolved types without re-scanning the page's posts.
    private func refreshPageTagTypes() {
        guard !pageTagCounts.isEmpty else { return }
        applyPageTags(from: pageTagCounts)
    }

    private func updatePageTagsForVisiblePage() {
        let start = (visiblePage - 1) * Self.pageSize
        guard start < posts.count else {
            if posts.isEmpty {
                updatePageTags(from: [])
                pageTagsResolveTask?.cancel()
            }
            return
        }
        let end = min(start + Self.pageSize, posts.count)
        let slice = Array(posts[start..<end])
        updatePageTags(from: slice)
        resolvePageTagTypes(forPage: visiblePage, loadGeneration: postsLoadGeneration)
    }

    private func updatePageTags(from posts: [BooruPost]) {
        var counts: [String: Int] = [:]
        for post in posts {
            for tag in post.tags where !tag.isEmpty {
                counts[tag, default: 0] += 1
            }
        }
        pageTagCounts = counts.map { (name: $0.key, count: $0.value) }
        applyPageTags(from: pageTagCounts)
    }

    /// Builds `pageTags` from cached counts + current tag types, skipping the re-render when nothing
    /// visible changed (e.g. a resolver batch didn't touch any tag on this page).
    private func applyPageTags(from counts: [(name: String, count: Int)]) {
        let newTags = counts.map { entry in
            BooruTag(name: entry.name, postCount: entry.count, type: tagType(for: entry.name))
        }
        tagChrome.replacePageTags(newTags)
    }

    /// Throttles the many incremental "types resolved" callbacks into at most one rebuild per
    /// `minInterval`, so the tag list re-lays-out a couple of times for a whole page instead of once
    /// per resolved chunk. Spaced-out callbacks (slow network) can't each trigger a relayout, and
    /// bursts collapse into a single trailing rebuild — both of which caused the scroll stutter.
    private func schedulePageTagsRefresh(forPage expectedPage: Int, loadGeneration: Int) {
        pageTagsRefreshTask?.cancel()
        let minInterval: TimeInterval = 0.6
        let elapsed = Date().timeIntervalSince(lastPageTagsRefresh)
        let delay = max(0, minInterval - elapsed)
        pageTagsRefreshTask = Task { [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self, !Task.isCancelled,
                  self.visiblePage == expectedPage,
                  loadGeneration == self.postsLoadGeneration else { return }
            self.lastPageTagsRefresh = Date()
            self.tagChrome.bumpTagIndexRevision()
            self.refreshPageTagTypes()
        }
    }

    /// Fetches types for tags on the current page that are unknown on any enabled server.
    private func resolvePageTagTypes(forPage expectedPage: Int, loadGeneration: Int) {
        pageTagsResolveTask?.cancel()

        let names = tagChrome.pageTags.map(\.name)
        guard !names.isEmpty else {
            tagChrome.setResolving(false)
            return
        }

        let hasMissing = names.contains { name in
            servers.contains { TagIndexStore.shared.type(for: name, siteID: $0.siteID) == nil }
        }
        guard hasMissing else {
            tagChrome.setResolving(false)
            return
        }

        tagChrome.setResolving(true)
        pageTagsResolveTask = Task {
            defer { tagChrome.setResolving(false) }

            await withTaskGroup(of: Void.self) { group in
                for server in servers {
                    group.addTask {
                        await TagIndexStore.shared.resolveMissing(
                            names: names,
                            site: server,
                            siteID: server.siteID
                        ) {
                            guard self.visiblePage == expectedPage,
                                  loadGeneration == self.postsLoadGeneration else { return }
                            self.schedulePageTagsRefresh(forPage: expectedPage, loadGeneration: loadGeneration)
                        }
                    }
                }
            }

            guard !Task.isCancelled,
                  visiblePage == expectedPage,
                  loadGeneration == postsLoadGeneration else { return }
            // Final authoritative refresh once every server finished resolving.
            pageTagsRefreshTask?.cancel()
            lastPageTagsRefresh = Date()
            tagChrome.bumpTagIndexRevision()
            refreshPageTagTypes()
        }
    }
}
