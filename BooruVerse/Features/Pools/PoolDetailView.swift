import SwiftUI

struct PoolDetailView: View {
    let pool: BooruPool

    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek
    @Environment(AppSettingsStore.self) private var settings

    @State private var model: BrowseViewModel

    init(pool: BooruPool, site: any BooruSite & BooruBrowsing) {
        self.pool = pool
        _model = State(initialValue: BrowseViewModel(site: site, mode: .pool, poolID: pool.id))
    }

    var body: some View {
        let _ = settings.revision

        PostResultsView(
            model: model,
            preferredCompactColumn: .constant(.detail),
            tilingMode: settings.galleryTilingMode,
            showsSidebarToggle: false,
            navigationTitle: pool.displayName
        )
        .task {
            model.loadTagCache()
            await model.bootstrapIfNeeded()
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
