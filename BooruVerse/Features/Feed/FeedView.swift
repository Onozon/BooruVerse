import SwiftUI

struct FeedView: View {
    @State private var model: BrowseViewModel

    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(AppSettingsStore.self) private var settings

    /// Morphs the selection highlight inside the shared period capsule.
    @Namespace private var periodSelection

    init(sites: [any BooruSite & BooruBrowsing]) {
        _model = State(initialValue: BrowseViewModel(servers: sites, mode: .popular))
    }

    var body: some View {
        // Observe rating so filtered posts refresh without the nuclear `revision` hammer.
        let _ = settings.ratingFilter

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

    @ViewBuilder
    private var periodPicker: some View {
        // One shared Liquid Glass capsule (like the top tab switcher), not three separate buttons.
        // https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
        if #available(iOS 26.0, macOS 26.0, *) {
            HStack(spacing: 0) {
                ForEach(PopularPeriod.allCases) { period in
                    periodSegment(period)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(4)
            .glassEffect(.regular.interactive(), in: Capsule())
            .animation(.snappy(duration: 0.25), value: model.popularPeriod)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        } else {
            Picker("Period", selection: periodBinding) {
                ForEach(PopularPeriod.allCases) { period in
                    Text(period.title).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func periodSegment(_ period: PopularPeriod) -> some View {
        let isSelected = model.popularPeriod == period

        return Button {
            Task { await model.setPopularPeriod(period) }
        } label: {
            Text(period.title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
                        // Subtle inner pill — no accent tint (avoids loud blue).
                        Capsule()
                            .fill(.primary.opacity(0.12))
                            .matchedGeometryEffect(id: "periodSelection", in: periodSelection)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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
