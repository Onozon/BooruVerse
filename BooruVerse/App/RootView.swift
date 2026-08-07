import SwiftUI

struct RootView: View {
    @State private var servers = ServerStore.shared
    @State private var gallery = GalleryCoordinator()
    @State private var peek = PeekCoordinator()
    @State private var navigation = AppNavigationCoordinator()

    private static func makeSites() -> [any BooruSite & BooruBrowsing] {
        ServerStore.shared.enabledServers.map { BooruSiteFactory.makeSite(for: $0) }
    }

    private var immersiveOverlayVisible: Bool {
        gallery.isPresented || peek.isPresented
    }

    var body: some View {
        ZStack {
            TabView(selection: $navigation.selectedTab) {
                FeedView(sites: RootView.makeSites())
                    .id(servers.revision)
                    .tag(AppTab.feed)
                    .tabItem {
                        Label("Feed", systemImage: "flame")
                    }

                BrowseView(sites: RootView.makeSites())
                    .id(servers.revision)
                    .tag(AppTab.browse)
                    .tabItem {
                        Label("Browse", systemImage: "magnifyingglass")
                    }

                PoolsView(sites: RootView.makeSites())
                    .id(servers.revision)
                    .tag(AppTab.pools)
                    .tabItem {
                        Label("Pools", systemImage: "books.vertical")
                    }

                FavoritesView(sites: RootView.makeSites())
                    .id(servers.revision)
                    .tag(AppTab.favorites)
                    .tabItem {
                        Label("Favorites", systemImage: "heart")
                    }

                SettingsPlaceholderView()
                    .tag(AppTab.settings)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape")
                    }
            }
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

    private func addTag(_ tag: String, from source: BrowseViewModel) async {
        peek.dismiss()
        gallery.dismiss()

        if source.mode == .browse {
            await source.addTag(tag)
        } else {
            // Favorites/Pools/Feed route the tag into the Browse tab and switch there.
            navigation.requestBrowseTag(tag)
        }
    }
}

#Preview {
    RootView()
}
