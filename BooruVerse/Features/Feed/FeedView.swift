import SwiftUI

struct FeedView: View {
    @Bindable var session: FeedSessionStore
    /// Keep-alive tabs stay mounted; only the selected tab should own window chrome.
    var isActive = true

    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(AppSettingsStore.self) private var settings

    /// Morphs the selection highlight inside the shared period capsule.
    @Namespace private var periodSelection

    private var model: BrowseViewModel { session.model }

    private var personalSelectionRevision: Int {
        PersonalFeedStore.shared.revision
    }

    private var savedSetsRevision: Int {
        SavedTagSetStore.shared.revision
    }

    private var showsPersonalEmptyState: Bool {
        model.feedChannel == .personal && PersonalFeedStore.shared.personalSets.isEmpty
    }

    var body: some View {
        // Observe rating so filtered posts refresh without the nuclear `revision` hammer.
        let _ = settings.ratingFilter
        let _ = personalSelectionRevision
        let _ = savedSetsRevision

        NavigationStack {
            Group {
                if showsPersonalEmptyState {
                    personalEmptyState
                } else {
                    PostResultsView(
                        model: model,
                        preferredCompactColumn: .constant(.detail),
                        tilingMode: settings.galleryTilingMode,
                        showsSidebarToggle: false,
                        navigationTitle: model.feedChannel == .personal ? "Personal" : "Popular",
                        contributesToolbar: isActive,
                        restoredScrollPostID: session.scrollAnchor(for: model.feedChannel),
                        onVisiblePostChange: { postID in
                            session.setScrollAnchor(postID, for: model.feedChannel)
                        }
                    )
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                channelPicker
            }
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
#endif
#if os(macOS)
            .navigationTitle("")
#else
            .navigationTitle(model.feedChannel == .personal ? "Personal" : "Popular")
#endif
        }
        .task(id: session.serversRevision) {
            model.loadTagCache()
            await model.bootstrapIfNeeded()
        }
        .onChange(of: settings.ratingFilter) { _, _ in
            Task { await model.applyRatingFilterChange() }
        }
        .onChange(of: personalSelectionRevision) { _, _ in
            Task { await model.reloadPersonalFeedIfNeeded() }
        }
        .onChange(of: savedSetsRevision) { _, _ in
            Task { await model.reloadPersonalFeedIfNeeded() }
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

    private var personalEmptyState: some View {
        ContentUnavailableView {
            Label("Personal Feed", systemImage: "person.crop.rectangle.stack")
        } description: {
            Text("Choose saved tag sets to build a mixed feed. Overlapping posts appear once, newest first.")
        } actions: {
            Button("Choose Tag Sets") {
                navigation.openPersonalFeedSets()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var channelPicker: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            HStack(spacing: 0) {
                ForEach(FeedChannel.allCases) { channel in
                    channelSegment(channel)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(4)
            .glassEffect(.regular.interactive(), in: Capsule())
            .animation(.snappy(duration: 0.25), value: model.feedChannel)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        } else {
            Picker("Feed", selection: channelBinding) {
                ForEach(FeedChannel.allCases) { channel in
                    Text(channel.title).tag(channel)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    @available(iOS 26.0, macOS 26.0, *)
    private func channelSegment(_ channel: FeedChannel) -> some View {
        let isSelected = model.feedChannel == channel

        return Button {
            Task { await selectChannel(channel) }
        } label: {
            Text(channel.title)
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .frame(maxWidth: .infinity, minHeight: 28)
                .padding(.horizontal, 6)
                .padding(.vertical, 6)
                .background {
                    if isSelected {
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

    private var channelBinding: Binding<FeedChannel> {
        Binding(
            get: { model.feedChannel },
            set: { newChannel in
                Task { await selectChannel(newChannel) }
            }
        )
    }

    private func selectChannel(_ channel: FeedChannel) async {
        guard channel != model.feedChannel else { return }
        session.persistChannel(channel)
        await model.setFeedChannel(channel)
    }
}

#Preview {
    FeedView(
        session: FeedSessionStore(
            sites: [BooruSiteFactory.previewSite],
            serversRevision: 0
        )
    )
    .environment(GalleryCoordinator())
    .environment(PeekCoordinator())
    .environment(AppNavigationCoordinator())
    .environment(AppSettingsStore.shared)
    .environment(ServerStore.shared)
}
