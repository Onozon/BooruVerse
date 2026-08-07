import SwiftUI

struct FavoritesView: View {
    @State private var model: BrowseViewModel
    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(AppSettingsStore.self) private var settings

    init(sites: [any BooruSite & BooruBrowsing]) {
        _model = State(initialValue: BrowseViewModel(servers: sites, mode: .favorites))
    }

    var body: some View {
        @Bindable var model = model
        let _ = settings.revision

        NavigationStack {
            PostResultsView(
                model: model,
                preferredCompactColumn: .constant(.detail),
                tilingMode: settings.galleryTilingMode,
                showsSidebarToggle: false,
                navigationTitle: "Favorites"
            )
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
#endif
        }
        .onAppear {
            model.loadTagCache()
            Task { await model.refreshPosts() }
        }
        .onChange(of: navigation.selectedTab) { _, tab in
            guard tab == .favorites else { return }
            Task { await model.refreshPosts() }
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
}

#Preview {
    FavoritesView(sites: [BooruSiteFactory.previewSite])
        .environment(GalleryCoordinator())
        .environment(PeekCoordinator())
        .environment(AppNavigationCoordinator())
        .environment(AppSettingsStore.shared)
        .environment(ServerStore.shared)
}
