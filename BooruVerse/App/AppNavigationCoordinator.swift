import SwiftUI

enum AppTab: Hashable, CaseIterable, Identifiable {
    case feed
    case browse
    case pools
    case favorites
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .feed: "Feed"
        case .browse: "Browse"
        case .pools: "Pools"
        case .favorites: "Favorites"
        case .settings: "Settings"
        }
    }

    var systemImage: String {
        switch self {
        case .feed: "flame"
        case .browse: "magnifyingglass"
        case .pools: "books.vertical"
        case .favorites: "heart"
        case .settings: "gearshape"
        }
    }
}

@MainActor
@Observable
final class AppNavigationCoordinator {
    var selectedTab: AppTab = .browse
    private(set) var focusBrowseDetail = false

    /// A tag requested from another tab (Favorites/Pools/Feed) to be added in Browse.
    var pendingBrowseTag: String?

    func focusBrowseResults() {
        focusBrowseDetail = true
    }

    func consumeBrowseDetailFocus() -> Bool {
        defer { focusBrowseDetail = false }
        return focusBrowseDetail
    }

    /// Routes a tag into the Browse tab and switches to it.
    func requestBrowseTag(_ tag: String) {
        pendingBrowseTag = tag
        focusBrowseDetail = true
        selectedTab = .browse
    }

    func consumePendingBrowseTag() -> String? {
        defer { pendingBrowseTag = nil }
        return pendingBrowseTag
    }
}
