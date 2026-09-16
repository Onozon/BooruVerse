import SwiftUI

struct FavoritesView: View {
    @Bindable var model: BrowseViewModel
    var scrollAnchor: Binding<String?>? = nil
    var isActive = true

    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.compactLayout) private var compactLayout

    @State private var favorites = FavoritePostStore.shared
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail

    /// iPhone / Mac narrow: Folders ↔ Posts. iPad / Mac wide: split.
    private var useSingleColumn: Bool {
#if os(macOS)
        compactLayout
#else
        horizontalSizeClass == .compact
#endif
    }

    var body: some View {
        let _ = settings.ratingFilter
        let _ = settings.showsFavoritesSidebar
        let _ = favorites.revision
        let _ = favorites.activeFolderID

        Group {
            if useSingleColumn {
                singleColumn
            } else {
                split
            }
        }
        .hideSystemSidebarToggle(true)
        .task {
            model.loadTagCache()
            await model.bootstrapIfNeeded()
        }
        .onChange(of: settings.ratingFilter) { _, _ in
            Task { await model.applyRatingFilterChange() }
        }
        .onChange(of: favorites.activeFolderID) { _, _ in
            Task { await model.loadFavorites() }
        }
        .onChange(of: favorites.revision) { _, _ in
            if model.mode == .favorites {
                Task { await model.loadFavorites() }
            }
        }
        .onChange(of: model.listGeneration) { _, _ in
            scrollAnchor?.wrappedValue = nil
            if gallery.isOpen(for: model) {
                gallery.dismiss()
            }
            if peek.isOpen(for: model) {
                peek.dismiss()
            }
        }
        .onChange(of: useSingleColumn) { _, isSingle in
            if isSingle {
                preferredCompactColumn = .detail
            }
        }
    }

    private var singleColumn: some View {
        NavigationStack {
            Group {
                if preferredCompactColumn == .sidebar {
                    FavoriteFolderSidebar {
                        preferredCompactColumn = .detail
                    }
#if os(macOS)
                    .navigationTitle("")
#else
                    .navigationTitle("Folders")
#endif
                    .modifier(CompactSidebarDismissGesture(
                        preferredCompactColumn: $preferredCompactColumn
                    ))
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                preferredCompactColumn = .detail
                            } label: {
                                Label("Posts", appIcon: AppIcon.posts)
                            }
                        }
                    }
                } else {
                    results
                        .toolbar {
                            ToolbarItem(placement: .navigation) {
                                Button {
                                    preferredCompactColumn = .sidebar
                                } label: {
                                    Label("Folders", appIcon: AppIcon.folder)
                                }
                            }
                        }
                }
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
#endif
        }
    }

    private var split: some View {
        HStack(spacing: 0) {
            if settings.showsFavoritesSidebar {
                FavoriteFolderSidebar()
                    .frame(minWidth: 200, idealWidth: 240, maxWidth: 280)
                Divider()
            }
#if os(macOS)
            NavigationStack { results }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
#else
            results
                .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
        }
        .animation(.easeInOut(duration: 0.2), value: settings.showsFavoritesSidebar)
    }

    private var results: some View {
        PostResultsView(
            model: model,
            preferredCompactColumn: $preferredCompactColumn,
            tilingMode: settings.galleryTilingMode,
            scaleSection: .favorites,
            showsSidebarToggle: false,
            enablesCompactSidebarSwipe: true,
            navigationTitle: folderTitle,
            isActive: isActive,
            contributesToolbar: isActive && useSingleColumn,
            restoredScrollPostID: scrollAnchor?.wrappedValue,
            onVisiblePostChange: { postID in
                scrollAnchor?.wrappedValue = postID
            }
        )
#if os(macOS)
        .navigationTitle("")
#endif
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
#endif
    }

    private var folderTitle: String {
        favorites.folders.first(where: { $0.id == favorites.activeFolderID })?.name ?? "Favorites"
    }
}

#Preview {
    FavoritesView(model: BrowseViewModel(site: BooruSiteFactory.previewSite, mode: .favorites))
        .environment(GalleryCoordinator())
        .environment(PeekCoordinator())
        .environment(AppNavigationCoordinator())
        .environment(AppSettingsStore.shared)
        .environment(ServerStore.shared)
}
