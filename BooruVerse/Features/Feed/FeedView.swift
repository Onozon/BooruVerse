import SwiftUI

struct FeedView: View {
    @State private var model: BrowseViewModel

    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(AppSettingsStore.self) private var settings

    init(sites: [any BooruSite & BooruBrowsing]) {
        _model = State(initialValue: BrowseViewModel(servers: sites, mode: .popular))
    }

    var body: some View {
        let _ = settings.revision

        NavigationStack {
            PostResultsView(
                model: model,
                preferredCompactColumn: .constant(.detail),
                tilingMode: settings.galleryTilingMode,
                showsSidebarToggle: false,
                navigationTitle: "Popular"
            )
            .safeAreaInset(edge: .top, spacing: 0) {
                periodPicker
            }
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
        .onChange(of: model.listGeneration) { _, _ in
            if gallery.isOpen(for: model) {
                gallery.dismiss()
            }
            if peek.isOpen(for: model) {
                peek.dismiss()
            }
        }
    }

    private var periodPicker: some View {
        Picker("Period", selection: periodBinding) {
            ForEach(PopularPeriod.allCases) { period in
                Text(period.title).tag(period)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var periodBinding: Binding<PopularPeriod> {
        Binding(
            get: { model.popularPeriod },
            set: { newPeriod in
                Task { await model.setPopularPeriod(newPeriod) }
            }
        )
    }
}

#Preview {
    FeedView(sites: [BooruSiteFactory.previewSite])
        .environment(GalleryCoordinator())
        .environment(PeekCoordinator())
        .environment(AppNavigationCoordinator())
        .environment(AppSettingsStore.shared)
        .environment(ServerStore.shared)
}
