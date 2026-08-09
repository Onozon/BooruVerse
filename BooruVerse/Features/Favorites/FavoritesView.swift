import SwiftUI

struct FavoritesView: View {
    @Bindable var model: BrowseViewModel
    var scrollAnchor: Binding<String?>? = nil
    var isActive = true

    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(AppSettingsStore.self) private var settings

    var body: some View {
        let _ = settings.ratingFilter

        NavigationStack {
            PostResultsView(
                model: model,
                preferredCompactColumn: .constant(.detail),
                tilingMode: settings.galleryTilingMode,
                showsSidebarToggle: false,
                navigationTitle: "Favorites",
                contributesToolbar: isActive,
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
        .task {
            model.loadTagCache()
            await model.bootstrapIfNeeded()
        }
        .onChange(of: settings.ratingFilter) { _, _ in
            Task { await model.applyRatingFilterChange() }
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
}

#Preview {
    FavoritesView(model: BrowseViewModel(site: BooruSiteFactory.previewSite, mode: .favorites))
        .environment(GalleryCoordinator())
        .environment(PeekCoordinator())
        .environment(AppNavigationCoordinator())
        .environment(AppSettingsStore.shared)
        .environment(ServerStore.shared)
}
