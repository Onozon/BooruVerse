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

    /// Phone / compact iPad: one screen at a time. Nested `NavigationSplitView` inside
    /// `TabView` on iPad often lays out the post grid at zero width (blank cells / stuck spinner).
    private var useSingleColumn: Bool {
#if os(macOS)
        compactLayout
#else
        horizontalSizeClass == .compact
#endif
    }

    var body: some View {
        let _ = settings.ratingFilter
        let _ = settings.showsBrowseSidebar

        Group {
            if useSingleColumn {
                singleColumnBrowse
            } else {
                splitBrowse
            }
        }
        .hideSystemSidebarToggle(true)
        .task {
            await reloadIfNeeded()
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
            Task { await reloadIfNeeded() }
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
        .alert(
            "Random Post",
            isPresented: Binding(
                get: { model.randomLoadError != nil },
                set: { if !$0 { model.randomLoadError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.randomLoadError = nil }
        } message: {
            Text(model.randomLoadError ?? "")
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

    /// Manual sidebar + detail. Avoids `NavigationSplitView` inside `TabView` (iPad layout bugs)
    /// and the system window sidebar toggle on Mac.
    private var splitBrowse: some View {
        HStack(spacing: 0) {
            if settings.showsBrowseSidebar {
                SearchSidebarView(
                    model: model,
                    preferredCompactColumn: $preferredCompactColumn
                )
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
#if os(macOS)
                .navigationTitle("")
#endif

                Divider()
            }

#if os(macOS)
            NavigationStack {
                resultsView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
#else
            resultsView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
#endif
        }
        .animation(.easeInOut(duration: 0.2), value: settings.showsBrowseSidebar)
    }

    /// Regular Mac / iPad chrome lives on the window or tab bar row, not a second header.
    private var resultsContributeToolbar: Bool {
        useSingleColumn
    }

    private var resultsView: some View {
        PostResultsView(
            model: model,
            preferredCompactColumn: $preferredCompactColumn,
            tilingMode: settings.galleryTilingMode,
            scaleSection: .browse,
            showsRandomPostButton: true,
            isActive: isActive,
            contributesToolbar: isActive && resultsContributeToolbar,
            restoredScrollPostID: scrollAnchor?.wrappedValue,
            onVisiblePostChange: { postID in
                scrollAnchor?.wrappedValue = postID
            }
        )
    }

    private func reloadIfNeeded() async {
        await model.bootstrapIfNeeded()
        applyPendingTagIfNeeded()
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
        .environment(PostFamilyStore.shared)
}
