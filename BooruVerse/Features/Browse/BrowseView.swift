import SwiftUI

struct BrowseView: View {
    @State private var model: BrowseViewModel
    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(AppSettingsStore.self) private var settings
    @State private var preferredCompactColumn: NavigationSplitViewColumn = .detail

    init(sites: [any BooruSite & BooruBrowsing]) {
        _model = State(initialValue: BrowseViewModel(servers: sites))
    }

    var body: some View {
        @Bindable var model = model
        let _ = settings.revision

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
        .task {
            await model.bootstrapIfNeeded()
            applyPendingTagIfNeeded()
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
