import Foundation

/// Session-scoped tab models and scroll anchors. Survives compact/regular chrome swaps.
@MainActor
@Observable
final class AppTabSessionStore {
    private(set) var serversRevision: Int
    let feed: FeedSessionStore
    private(set) var browseModel: BrowseViewModel
    private(set) var favoritesModel: BrowseViewModel

    /// Last focused post in Browse / Favorites grids.
    var browseScrollAnchor: String?
    var favoritesScrollAnchor: String?

    init(sites: [any BooruSite & BooruBrowsing], serversRevision: Int) {
        self.serversRevision = serversRevision
        feed = FeedSessionStore(sites: sites, serversRevision: serversRevision)
        browseModel = BrowseViewModel(servers: sites, mode: .browse)
        favoritesModel = BrowseViewModel(servers: sites, mode: .favorites)
    }

    func syncServersIfNeeded(sites: [any BooruSite & BooruBrowsing], revision: Int) {
        guard revision != serversRevision else { return }
        serversRevision = revision
        feed.syncServersIfNeeded(sites: sites, revision: revision)
        browseModel = BrowseViewModel(servers: sites, mode: .browse)
        favoritesModel = BrowseViewModel(servers: sites, mode: .favorites)
        browseScrollAnchor = nil
        favoritesScrollAnchor = nil
    }
}
