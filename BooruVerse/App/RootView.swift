import SwiftUI

struct RootView: View {
    @State private var servers = ServerStore.shared
    @State private var gallery = GalleryCoordinator()
    @State private var peek = PeekCoordinator()
    @State private var navigation = AppNavigationCoordinator()
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
                .environment(AppSettingsStore.shared)
                .environment(servers)
                .disabled(immersiveOverlayVisible)
                .onChange(of: servers.revision) { _, _ in
                    gallery.dismiss()
                    peek.dismiss()
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
                        withAnimation(.easeInOut(duration: 0.25)) {
                            gallery.dismiss()
                        }
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .ignoresSafeArea()
                .zIndex(1000)
                .transition(.opacity)
            }
        }
#if os(macOS)
        .toolbar(immersiveOverlayVisible ? .hidden : .visible, for: .windowToolbar)
#endif
        .animation(.easeInOut(duration: 0.2), value: peek.isPresented)
        .animation(.easeInOut(duration: 0.25), value: gallery.isPresented)
    }

    @ViewBuilder
    private var tabChrome: some View {
#if os(macOS)
        if compactLayout {
            // Phone-like: content + bottom tab bar (native Mac TabView stays top-only).
            VStack(spacing: 0) {
                tabContent
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                if !immersiveOverlayVisible {
                    MacCompactTabBar(selection: $navigation.selectedTab)
                }
            }
        } else {
            systemTabView
        }
#else
        systemTabView
#endif
    }

    private var systemTabView: some View {
        TabView(selection: $navigation.selectedTab) {
            FeedView(sites: RootView.makeSites())
                .id(servers.revision)
                .tag(AppTab.feed)
                .tabItem { Label(AppTab.feed.title, systemImage: AppTab.feed.systemImage) }

            BrowseView(sites: RootView.makeSites())
                .id(servers.revision)
                .tag(AppTab.browse)
                .tabItem { Label(AppTab.browse.title, systemImage: AppTab.browse.systemImage) }

            PoolsView(sites: RootView.makeSites())
                .id(servers.revision)
                .tag(AppTab.pools)
                .tabItem { Label(AppTab.pools.title, systemImage: AppTab.pools.systemImage) }

            FavoritesView(sites: RootView.makeSites())
                .id(servers.revision)
                .tag(AppTab.favorites)
                .tabItem { Label(AppTab.favorites.title, systemImage: AppTab.favorites.systemImage) }

            SettingsPlaceholderView()
                .tag(AppTab.settings)
                .tabItem { Label(AppTab.settings.title, systemImage: AppTab.settings.systemImage) }
        }
    }

    /// Shared page body for the Mac compact bottom-tab chrome (no system TabView).
    @ViewBuilder
    private var tabContent: some View {
        switch navigation.selectedTab {
        case .feed:
            FeedView(sites: RootView.makeSites())
                .id(servers.revision)
        case .browse:
            BrowseView(sites: RootView.makeSites())
                .id(servers.revision)
        case .pools:
            PoolsView(sites: RootView.makeSites())
                .id(servers.revision)
        case .favorites:
            FavoritesView(sites: RootView.makeSites())
                .id(servers.revision)
        case .settings:
            SettingsPlaceholderView()
        }
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
                            .font(.system(size: 17, weight: .medium))
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
