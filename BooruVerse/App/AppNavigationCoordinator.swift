import SwiftUI

enum AppTab: Hashable {
    case feed
    case browse
    case pools
    case favorites
    case settings
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
