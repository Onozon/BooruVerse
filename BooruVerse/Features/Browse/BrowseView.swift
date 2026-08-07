import SwiftUI

struct BrowseView: View {
    @State private var model: BrowseViewModel
    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.compactLayout) private var compactLayout
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail

    init(sites: [any BooruSite & BooruBrowsing]) {
        _model = State(initialValue: BrowseViewModel(servers: sites))
    }

    /// Phone-like single column. NavigationSplitView does not collapse on macOS the way
    /// it does on iPadOS, so Mac narrow windows use an explicit one-screen switcher.
    private var useSingleColumn: Bool {
#if os(macOS)
        compactLayout
#else
        false
#endif
    }

    var body: some View {
        @Bindable var model = model
        let _ = settings.ratingFilter

        Group {
            if useSingleColumn {
                singleColumnBrowse
            } else {
                splitBrowse
            }
        }
        .task {
            await model.bootstrapIfNeeded()
            applyPendingTagIfNeeded()
        }
        .onChange(of: useSingleColumn) { _, isSingle in
            if isSingle {
                preferredCompactColumn = .detail
            }
        }
        .onChange(of: navigation.selectedTab) { _, tab in
            guard tab == .browse else { return }
            applyPendingTagIfNeeded()
            if navigation.consumeBrowseDetailFocus() {
                preferredCompactColumn = .detail
            }
        }
        .onChange(of: navigation.pendingBrowseTag) { _, _ in
            applyPendingTagIfNeeded()
        }
        .onChange(of: model.listGeneration) { _, _ in
            if gallery.isOpen(for: model) {
                gallery.dismiss()
            }
            if peek.isOpen(for: model) {
                peek.dismiss()
            }
        }
    }

    /// iPhone-style: only one of search / posts is mounted, so toolbars don't leak.
    private var singleColumnBrowse: some View {
        NavigationStack {
            Group {
                if preferredCompactColumn == .sidebar {
                    SearchSidebarView(
                        model: model,
                        preferredCompactColumn: $preferredCompactColumn
                    )
                    .navigationTitle(model.displayName)
                } else {
                    PostResultsView(
                        model: model,
                        preferredCompactColumn: $preferredCompactColumn,
                        tilingMode: settings.galleryTilingMode
                    )
                }
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
#endif
        }
    }

    private var splitBrowse: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            NavigationStack {
                SearchSidebarView(
                    model: model,
                    preferredCompactColumn: $preferredCompactColumn
                )
                .navigationTitle(model.displayName)
#if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
#endif
            }
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 360)
#endif
        } detail: {
            NavigationStack {
                PostResultsView(
                    model: model,
                    preferredCompactColumn: $preferredCompactColumn,
                    tilingMode: settings.galleryTilingMode
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    private func applyPendingTagIfNeeded() {
        guard let tag = navigation.consumePendingBrowseTag() else { return }
        Task { await model.addTag(tag) }
    }
}

#Preview {
    BrowseView(sites: [BooruSiteFactory.previewSite])
        .environment(GalleryCoordinator())
        .environment(PeekCoordinator())
        .environment(AppNavigationCoordinator())
        .environment(AppSettingsStore.shared)
        .environment(ServerStore.shared)
}
