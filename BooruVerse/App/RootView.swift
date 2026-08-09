import SwiftUI

struct RootView: View {
    @State private var servers = ServerStore.shared
    @State private var gallery = GalleryCoordinator()
    @State private var peek = PeekCoordinator()
    @State private var navigation = AppNavigationCoordinator()
    @State private var sessions = AppTabSessionStore(
        sites: RootView.makeSites(),
        serversRevision: ServerStore.shared.revision
    )
    @Environment(\.compactLayout) private var compactLayout

    private static func makeSites() -> [any BooruSite & BooruBrowsing] {
        ServerStore.shared.enabledServers.map { BooruSiteFactory.makeSite(for: $0) }
    }

    private var immersiveOverlayVisible: Bool {
        gallery.isPresented || peek.isPresented
    }

    var body: some View {
        ZStack {
            tabChrome
                .environment(gallery)
                .environment(peek)
                .environment(navigation)
                .environment(servers)
                .disabled(immersiveOverlayVisible)
                .onChange(of: servers.revision) { _, revision in
                    gallery.dismiss()
                    peek.dismiss()
                    sessions.syncServersIfNeeded(
                        sites: RootView.makeSites(),
                        revision: revision
                    )
                }
            if let model = peek.model, let post = peek.activePost {
                PostPeekOverlay(
                    model: model,
                    post: post,
                    onAddTag: { tag in
                        await addTag(tag, from: model)
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
                    onAddTag: { tag in
                        await addTag(tag, from: model)
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
#if os(macOS)
        .toolbar {
            if !compactLayout, !immersiveOverlayVisible {
                ToolbarItem(placement: .principal) {
                    MacTitlebarTabBar(selection: $navigation.selectedTab)
                }
            }
        }
        .toolbar(immersiveOverlayVisible ? .hidden : .visible, for: .windowToolbar)
        // Avoid animating toolbar hide — it left a tab-sized top inset under the gallery.
        .animation(nil, value: immersiveOverlayVisible)
        .modifier(MacHideWindowTitle())
        // Always strip the system split-view toggle; Browse uses its own button.
        .toolbar(removing: .sidebarToggle)
#endif
        .animation(.easeInOut(duration: 0.2), value: peek.isPresented)
        .animation(gallery.isPresented ? nil : .easeInOut(duration: 0.25), value: gallery.isPresented)
    }

    @ViewBuilder
    private var tabChrome: some View {
#if os(macOS)
        VStack(spacing: 0) {
            keptAliveTabPages
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if compactLayout, !immersiveOverlayVisible {
                MacCompactTabBar(selection: $navigation.selectedTab)
            }
        }
#else
        systemTabView
#endif
    }

#if os(iOS)
    private var systemTabView: some View {
        TabView(selection: $navigation.selectedTab) {
            FeedView(session: sessions.feed)
                .tag(AppTab.feed)
                .tabItem { Label(AppTab.feed.title, systemImage: AppTab.feed.systemImage) }

            BrowseView(model: sessions.browseModel)
                .tag(AppTab.browse)
                .tabItem { Label(AppTab.browse.title, systemImage: AppTab.browse.systemImage) }

            PoolsView(sites: RootView.makeSites())
                .id(servers.revision)
                .tag(AppTab.pools)
                .tabItem { Label(AppTab.pools.title, systemImage: AppTab.pools.systemImage) }

            FavoritesView(model: sessions.favoritesModel)
                .tag(AppTab.favorites)
                .tabItem { Label(AppTab.favorites.title, systemImage: AppTab.favorites.systemImage) }

            SettingsPlaceholderView()
                .tag(AppTab.settings)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
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
            tabPage(.pools) {
                PoolsView(sites: RootView.makeSites(), isActive: navigation.selectedTab == .pools)
                    .id(servers.revision)
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

    private func addTag(_ tag: String, from source: BrowseViewModel) async {
        peek.dismiss()
        gallery.dismiss()

        if source.mode == .browse {
            await source.addTag(tag)
        } else {
            navigation.requestBrowseTag(tag)
        }
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

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Label(tab.title, systemImage: tab.systemImage)
                        .labelStyle(.titleAndIcon)
                        .font(.system(size: 12, weight: selection == tab ? .semibold : .regular))
                        .imageScale(.medium)
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
        .frame(maxWidth: .infinity)
    }
}

/// iOS-style bottom tab bar for narrow Mac windows.
private struct MacCompactTabBar: View {
    @Binding var selection: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 16, weight: .medium))
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
