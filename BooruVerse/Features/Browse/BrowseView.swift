import SwiftUI

struct BrowseView: View {
    @Bindable var model: BrowseViewModel
    var scrollAnchor: Binding<String?>? = nil
    var isActive = true

    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.compactLayout) private var compactLayout
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail
    /// macOS wide: custom split (no NavigationSplitView — its system toggle leaks to other tabs).
    @State private var showsMacSidebar = true

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
        let _ = settings.ratingFilter

        Group {
            if useSingleColumn {
                singleColumnBrowse
            } else {
#if os(macOS)
                macSplitBrowse
#else
                splitBrowse
#endif
            }
        }
        .hideSystemSidebarToggle(true)
        .task {
            await model.bootstrapIfNeeded()
            applyPendingTagIfNeeded()
        }
        .onChange(of: settings.ratingFilter) { _, _ in
            Task { await model.applyRatingFilterChange() }
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
            scrollAnchor?.wrappedValue = nil
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
#if os(macOS)
                    .navigationTitle("")
#else
                    .navigationTitle(model.displayName)
#endif
                } else {
                    resultsView
                }
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
#endif
        }
    }

#if os(macOS)
    /// Manual sidebar + detail. Avoids NavigationSplitView's window sidebar toggle.
    private var macSplitBrowse: some View {
        HStack(spacing: 0) {
            if showsMacSidebar {
                SearchSidebarView(
                    model: model,
                    preferredCompactColumn: $preferredCompactColumn
                )
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                .navigationTitle("")

                Divider()
            }

            NavigationStack {
                resultsView
                    .toolbar {
                        if isActive {
                            ToolbarItem(placement: .navigation) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        showsMacSidebar.toggle()
                                    }
                                } label: {
                                    Label(
                                        "Toggle Sidebar",
                                        systemImage: "sidebar.left"
                                    )
                                }
                                .help("Toggle Sidebar")
                            }
                        }
                    }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
#else
    private var splitBrowse: some View {
        NavigationSplitView(preferredCompactColumn: $preferredCompactColumn) {
            NavigationStack {
                SearchSidebarView(
                    model: model,
                    preferredCompactColumn: $preferredCompactColumn
                )
                .navigationTitle(model.displayName)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.background, for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
            }
        } detail: {
            NavigationStack {
                resultsView
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
#endif

    private var resultsView: some View {
        PostResultsView(
            model: model,
            preferredCompactColumn: $preferredCompactColumn,
            tilingMode: settings.galleryTilingMode,
            contributesToolbar: isActive,
            restoredScrollPostID: scrollAnchor?.wrappedValue,
            onVisiblePostChange: { postID in
                scrollAnchor?.wrappedValue = postID
            }
        )
    }

    private func applyPendingTagIfNeeded() {
        guard let tag = navigation.consumePendingBrowseTag() else { return }
        Task { await model.addTag(tag) }
    }
}

#Preview {
    BrowseView(model: BrowseViewModel(site: BooruSiteFactory.previewSite))
        .environment(GalleryCoordinator())
        .environment(PeekCoordinator())
        .environment(AppNavigationCoordinator())
        .environment(AppSettingsStore.shared)
        .environment(ServerStore.shared)
}
