import SwiftUI

struct RootView: View {
    @State private var servers = ServerStore.shared
    @State private var gallery = GalleryCoordinator()
    @State private var peek = PeekCoordinator()
    @State private var navigation = AppNavigationCoordinator()
    @State private var favorites = FavoritePostStore.shared
    @State private var sessions = AppTabSessionStore(
        sites: RootView.makeSites(),
        serversRevision: ServerStore.shared.revision
    )
    @State private var families = PostFamilyStore.shared
    @State private var settings = AppSettingsStore.shared
    @Environment(\.compactLayout) private var compactLayout
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private static func makeSites() -> [any BooruSite & BooruBrowsing] {
        ServerStore.shared.enabledServers.map { BooruSiteFactory.makeSite(for: $0) }
    }

    private var immersiveOverlayVisible: Bool {
        gallery.isPresented || peek.isPresented
    }

    private var visibleTabs: [AppTab] {
        AppTab.visibleTabs(flavors: Set(servers.enabledServers.map(\.flavor)))
    }

    /// iPad regular: draw sidebar / refresh on the tab-bar row, not in a second header.
    private var showsRegularTabChrome: Bool {
        (navigation.selectedTab == .browse || navigation.selectedTab == .favorites)
            && horizontalSizeClass != .compact
            && !immersiveOverlayVisible
    }

    var body: some View {
        ZStack {
            tabChrome
                .disabled(immersiveOverlayVisible)
                .onChange(of: servers.revision) { _, revision in
                    gallery.dismiss()
                    peek.dismiss()
                    sessions.syncServersIfNeeded(
                        sites: RootView.makeSites(),
                        revision: revision
                    )
                    if !visibleTabs.contains(navigation.selectedTab) {
                        navigation.selectedTab = .browse
                    }
                }
            if let model = peek.model, let post = peek.activePost {
                PostPeekOverlay(
                    model: model,
                    post: post,
                    browseModel: sessions.browseModel,
                    onToggleTag: { tag in
                        await toggleBrowseTag(tag)
                    },
                    onDismiss: { peek.dismiss() }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black.opacity(0.001))
                .ignoresSafeArea()
                .zIndex(999)
                .transition(.opacity)
            }

            if let model = gallery.model, let postID = gallery.selectedPostID {
                PostGalleryViewer(
                    model: model,
                    posts: gallery.posts,
                    selectedPostID: Binding(
                        get: { gallery.selectedPostID ?? postID },
                        set: { gallery.setSelectedPostID($0) }
                    ),
                    browseModel: sessions.browseModel,
                    onToggleTag: { tag in
                        await toggleBrowseTag(tag)
                    },
                    onPostsUpdated: {
                        gallery.syncFromModel()
                    },
                    onDismiss: {
                        // LazyPager already played the swipe-away animation; avoid a second
                        // fade that briefly resurrects the image.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            gallery.dismiss()
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .zIndex(1000)
            }
        }
        // Shared by tab chrome and immersive overlays (gallery sits outside tabChrome).
        .environment(AppSettingsStore.shared)
        .environment(servers)
        .environment(gallery)
        .environment(peek)
        .environment(navigation)
        .environment(SelectionStore.shared)
        .environment(DownloadStore.shared)
        .environment(families)
#if os(macOS)
        .toolbar {
            if !compactLayout, !immersiveOverlayVisible {
                if navigation.selectedTab == .browse || navigation.selectedTab == .favorites {
                    ToolbarItem(placement: .navigation) {
                        macToolbarEnvironment {
                            RegularBrowseLeadingButtons(
                                sidebar: navigation.selectedTab == .favorites ? .favorites : .browse,
                                model: sessions.browseModel,
                                showsRandom: navigation.selectedTab == .browse
                            )
                        }
                    }
                }
                ToolbarItem(placement: .principal) {
                    MacTitlebarTabBar(
                        selection: $navigation.selectedTab,
                        tabs: visibleTabs,
                        browseTagCount: sessions.browseModel.tagQuery.tags.count
                    )
                }
                if navigation.selectedTab == .browse {
                    ToolbarItemGroup(placement: .primaryAction) {
                        macToolbarEnvironment {
                            regularTrailingItems(for: sessions.browseModel)
                        }
                    }
                } else if navigation.selectedTab == .favorites {
                    ToolbarItemGroup(placement: .primaryAction) {
                        macToolbarEnvironment {
                            regularTrailingItems(for: sessions.favoritesModel)
                        }
                    }
                }
            }
        }
        .toolbar(immersiveOverlayVisible ? .hidden : .visible, for: .windowToolbar)
        // Avoid animating toolbar hide — it left a tab-sized top inset under the gallery.
        .animation(nil, value: immersiveOverlayVisible)
        // Sidebar width changes must not animate the titlebar tab capsule.
        .animation(nil, value: settings.showsBrowseSidebar)
        .animation(nil, value: settings.showsFavoritesSidebar)
        .modifier(MacHideWindowTitle())
        // Always strip the system split-view toggle; Browse uses its own button.
        .toolbar(removing: .sidebarToggle)
#endif
        .animation(.easeInOut(duration: 0.2), value: peek.isPresented)
        .animation(gallery.isPresented ? nil : .easeInOut(duration: 0.25), value: gallery.isPresented)
        .sheet(isPresented: $favorites.isPresentingFolderPicker, onDismiss: {
            if !favorites.pendingAdds.isEmpty {
                favorites.cancelPendingAdd()
            }
        }) {
            FavoriteFolderPickerSheet()
        }
    }

    @ViewBuilder
    private var tabChrome: some View {
#if os(macOS)
        VStack(spacing: 0) {
            keptAliveTabPages
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if compactLayout, !immersiveOverlayVisible {
                MacCompactTabBar(
                    selection: $navigation.selectedTab,
                    tabs: visibleTabs,
                    browseTagCount: sessions.browseModel.tagQuery.tags.count
                )
            }
        }
#else
        systemTabView
            .overlay(alignment: .topLeading) {
                if showsRegularTabChrome {
                    RegularBrowseLeadingButtons(
                        sidebar: navigation.selectedTab == .favorites ? .favorites : .browse,
                        model: sessions.browseModel,
                        showsRandom: navigation.selectedTab == .browse
                    )
                    .padding(.leading, 20)
                    .padding(.top, 10)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showsRegularTabChrome {
                    RegularBrowseTrailingButtons(
                        model: navigation.selectedTab == .favorites
                            ? sessions.favoritesModel
                            : sessions.browseModel
                    )
                    .padding(.trailing, 20)
                    .padding(.top, 10)
                }
            }
#endif
    }

#if os(iOS)
    private var systemTabView: some View {
        TabView(selection: $navigation.selectedTab) {
            FeedView(session: sessions.feed)
                .tag(AppTab.feed)
                .tabItem { Label(AppTab.feed.title, appIcon: AppTab.feed.icon) }

            BrowseView(model: sessions.browseModel)
                .tag(AppTab.browse)
                .tabItem { Label(AppTab.browse.title, appIcon: AppTab.browse.icon) }
                .badge(sessions.browseModel.tagQuery.tags.isEmpty
                       ? 0
                       : sessions.browseModel.tagQuery.tags.count)

            if visibleTabs.contains(.pools) {
                PoolsView(sites: RootView.makeSites())
                    .id(servers.revision)
                    .tag(AppTab.pools)
                    .tabItem { Label(AppTab.pools.title, appIcon: AppTab.pools.icon) }
            }

            FavoritesView(model: sessions.favoritesModel)
                .tag(AppTab.favorites)
                .tabItem { Label(AppTab.favorites.title, appIcon: AppTab.favorites.icon) }

            SettingsPlaceholderView()
                .tag(AppTab.settings)
                .tabItem { Label(AppTab.settings.title, appIcon: AppTab.settings.icon) }
        }
    }
#endif

    private var keptAliveTabPages: some View {
        ZStack {
            tabPage(.feed) {
                FeedView(
                    session: sessions.feed,
                    isActive: navigation.selectedTab == .feed
                )
            }
            tabPage(.browse) {
                BrowseView(
                    model: sessions.browseModel,
                    scrollAnchor: Binding(
                        get: { sessions.browseScrollAnchor },
                        set: { sessions.browseScrollAnchor = $0 }
                    ),
                    isActive: navigation.selectedTab == .browse
                )
            }
            if visibleTabs.contains(.pools) {
                tabPage(.pools) {
                    PoolsView(sites: RootView.makeSites(), isActive: navigation.selectedTab == .pools)
                        .id(servers.revision)
                }
            }
            tabPage(.favorites) {
                FavoritesView(
                    model: sessions.favoritesModel,
                    scrollAnchor: Binding(
                        get: { sessions.favoritesScrollAnchor },
                        set: { sessions.favoritesScrollAnchor = $0 }
                    ),
                    isActive: navigation.selectedTab == .favorites
                )
            }
            tabPage(.settings) {
                SettingsPlaceholderView()
            }
        }
    }

    @ViewBuilder
    private func tabPage<Content: View>(_ tab: AppTab, @ViewBuilder content: () -> Content) -> some View {
        let isSelected = navigation.selectedTab == tab
        content()
            .opacity(isSelected ? 1 : 0)
            .allowsHitTesting(isSelected)
            .accessibilityHidden(!isSelected)
            .zIndex(isSelected ? 1 : 0)
    }

    private func toggleBrowseTag(_ tag: String) async {
        await sessions.browseModel.toggleTag(tag)
    }

    /// Window toolbar is hosted outside the `RootView` environment on macOS.
    private func macToolbarEnvironment<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .environment(AppSettingsStore.shared)
            .environment(servers)
            .environment(gallery)
            .environment(peek)
            .environment(navigation)
            .environment(SelectionStore.shared)
            .environment(DownloadStore.shared)
            .environment(families)
    }

    @ViewBuilder
    private func regularTrailingItems(for model: BrowseViewModel) -> some View {
        if model.isLoading || model.isLoadingMore {
            ProgressView()
                .controlSize(.small)
        }
        SelectionChromeView()
        RefreshPostsButton(model: model)
    }
}

#if os(macOS)
private struct MacHideWindowTitle: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15.0, *) {
            content.toolbar(removing: .title)
        } else {
            content
        }
    }
}

/// Centered titlebar tab switcher (same row as traffic lights).
private struct MacTitlebarTabBar: View {
    @Binding var selection: AppTab
    var tabs: [AppTab] = AppTab.allCases
    var browseTagCount: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                } label: {
                    HStack(spacing: 4) {
                        Label(tab.title, appIcon: tab.icon)
                            .labelStyle(.titleAndIcon)
                            .font(.system(size: 12, weight: selection == tab ? .semibold : .regular))
                            .imageScale(.medium)
                        if tab == .browse, browseTagCount > 0 {
                            Text("\(browseTagCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(Color.accentColor))
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background {
                        if selection == tab {
                            Capsule().fill(.primary.opacity(0.14))
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(selection == tab ? .primary : .secondary)
                .help(tab.title)
            }
        }
        // Inset so the selection pill on Feed/Settings doesn't kiss the toolbar capsule edge.
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .frame(height: ChromeBarMetrics.height)
        .transaction { $0.animation = nil }
    }
}

/// iOS-style bottom tab bar for narrow Mac windows.
private struct MacCompactTabBar: View {
    @Binding var selection: AppTab
    var tabs: [AppTab] = AppTab.allCases
    var browseTagCount: Int = 0

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        ZStack(alignment: .topTrailing) {
                            Image(tab.icon)
                                .resizable()
                                .renderingMode(.template)
                                .frame(width: 16, height: 16)
                            if tab == .browse, browseTagCount > 0 {
                                Text("\(min(browseTagCount, 99))")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 3)
                                    .padding(.vertical, 1)
                                    .background(Capsule().fill(Color.accentColor))
                                    .offset(x: 8, y: -6)
                            }
                        }
                        Text(tab.title)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .foregroundStyle(selection == tab ? Color.accentColor : Color.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .background(.bar)
    }
}
#endif

#Preview {
    RootView()
}
