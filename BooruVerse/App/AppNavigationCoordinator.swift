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

    var icon: String {
        switch self {
        case .feed: AppIcon.feed
        case .browse: AppIcon.browse
        case .pools: AppIcon.pools
        case .favorites: AppIcon.favorites
        case .settings: AppIcon.settings
        }
    }

    /// Tabs that make sense for the currently enabled servers (e.g. hide Pools without Moebooru).
    static func visibleTabs(flavors: Set<BooruAPIFlavor>) -> [AppTab] {
        allCases.filter { tab in
            if tab == .pools {
                return flavors.contains(where: \.supportsPools)
            }
            return true
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

    /// When set, Settings should push the Personal Feed sets picker.
    private(set) var pendingSettingsRoute: SettingsRoute?

    enum SettingsRoute: Hashable {
        case personalFeedSets
    }

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

    func openPersonalFeedSets() {
        pendingSettingsRoute = .personalFeedSets
        selectedTab = .settings
    }

    func consumePendingSettingsRoute() -> SettingsRoute? {
        defer { pendingSettingsRoute = nil }
        return pendingSettingsRoute
    }
}
