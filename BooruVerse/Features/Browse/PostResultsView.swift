import SwiftUI

struct PostResultsView: View {
    @Bindable var model: BrowseViewModel
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    let tilingMode: GalleryTilingMode
    var showsSidebarToggle = true
    var navigationTitle = "Posts"

    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek
    @Environment(ServerStore.self) private var serverStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var scrollRequest: String?
    @State private var suppressGridScroll = false
    @State private var widthUpdateToken = 0

    private let adaptiveColumns = [GridItem(.adaptive(minimum: GalleryLayoutMetrics.minTileWidth), spacing: GalleryLayoutMetrics.spacing)]

    /// Narrow / phone-like chrome: one card per row, progressive preview → viewer upgrade.
    private var isCompactGallery: Bool {
        horizontalSizeClass == .compact
    }

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage = model.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.subheadline)
                    .foregroundStyle(.orange)
                    .padding()
            }

            postsScrollArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle(navigationTitle)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsSidebarToggle && horizontalSizeClass == .compact)
        .toolbarBackground(.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
#endif
        .hideSystemSidebarToggle(showsSidebarToggle && horizontalSizeClass == .compact)
        .modifier(CompactSidebarPresentGesture(
            preferredCompactColumn: $preferredCompactColumn,
            isEnabled: showsSidebarToggle
        ))
        .toolbar {
            if showsSidebarToggle, horizontalSizeClass == .compact {
                ToolbarItem(placement: .navigation) {
                    Button {
                        preferredCompactColumn = .sidebar
                    } label: {
                        Label("Search", systemImage: "line.3.horizontal")
                    }
                }
            }

            ToolbarItem(placement: .automatic) {
                if model.isLoading || model.isLoadingMore {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await model.refreshPosts() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
            }
        }
    }

    @ViewBuilder
    private var postsScrollArea: some View {
        if model.isLoading && model.posts.isEmpty {
            ProgressView(loadingTitle)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            GeometryReader { geometry in
                let stableWidth = geometry.size.width
                let contentWidth = max(0, stableWidth - GalleryLayoutMetrics.gridPadding * 2)

                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(alignment: .leading, spacing: 0) {
                            if model.posts.isEmpty {
                                ContentUnavailableView(
                                    emptyStateTitle,
                                    systemImage: emptyStateIcon,
                                    description: Text(emptyStateDescription)
                                )
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 48)
                            } else {
                                galleryContent(contentWidth: contentWidth)
                                    .frame(width: contentWidth, alignment: .topLeading)
                                    .padding(GalleryLayoutMetrics.gridPadding)

                                if model.isLoadingMore {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 16)
                                }
                            }
                        }
                        .frame(width: stableWidth, alignment: .topLeading)
                    }
                    .onChange(of: scrollRequest) { _, postID in
                        guard let postID else { return }
                        scrollToPost(postID, using: proxy)
                        scrollRequest = nil
                    }
                    .refreshable {
                        await model.refreshPosts()
                    }
                }
                .onChange(of: geometry.size.width) { _, _ in
                    suppressGridScrollDuringResize()
                }
            }
        }
    }

    private func suppressGridScrollDuringResize() {
        suppressGridScroll = true
        scrollRequest = nil
        widthUpdateToken += 1
        let token = widthUpdateToken

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard token == widthUpdateToken else { return }
            suppressGridScroll = false
        }
    }

    @ViewBuilder
    private func galleryContent(contentWidth: CGFloat) -> some View {
        if isCompactGallery {
            compactSingleColumnGallery(contentWidth: contentWidth)
        } else {
            switch tilingMode {
            case .adaptive:
                adaptiveGallery
            case .columns:
                columnsGallery(contentWidth: contentWidth)
            }
        }
    }

    /// One full-width card per row; preview first, viewer upgrade while on screen.
    private func compactSingleColumnGallery(contentWidth: CGFloat) -> some View {
        LazyVStack(spacing: GalleryLayoutMetrics.spacing) {
            ForEach(model.posts, id: \.globalID) { post in
                postCell(for: post, tileWidth: contentWidth, upgradesToViewer: true)
            }
        }
        .frame(width: contentWidth, alignment: .topLeading)
    }

    private var adaptiveGallery: some View {
        LazyVGrid(columns: adaptiveColumns, spacing: GalleryLayoutMetrics.spacing) {
            ForEach(model.posts, id: \.globalID) { post in
                postCell(for: post, upgradesToViewer: false)
            }
        }
    }

    private func columnsGallery(contentWidth: CGFloat) -> some View {
        ColumnsMasonryGallery(
            posts: model.posts,
            listGeneration: model.listGeneration,
            contentWidth: contentWidth,
            borderSignature: serverStore.enabledCount,
            upgradesToViewer: false,
            borderColorProvider: { post in borderColor(for: post) },
            onTap: { openGallery(post: $0) },
            onLongPress: { openPeek(for: $0) },
            onAppearPost: { handlePostAppear(for: $0) }
        )
        .equatable()
    }

    @ViewBuilder
    private func postCell(
        for post: BooruPost,
        tileWidth: CGFloat? = nil,
        upgradesToViewer: Bool
    ) -> some View {
        PostThumbnailCell(
            post: post,
            tileWidth: tileWidth,
            borderColor: borderColor(for: post),
            upgradesToViewer: upgradesToViewer,
            onTap: { openGallery(post: post) },
            onLongPress: { openPeek(for: post) }
        )
        .id(post.globalID)
        .onAppear {
            handlePostAppear(for: post)
        }
    }

    /// Per-server border color, shown only when 2+ servers are enabled.
    private func borderColor(for post: BooruPost) -> Color? {
        guard serverStore.enabledCount >= 2 else { return nil }
        return serverStore.color(for: post.serverID)
    }

    private func handlePostAppear(for post: BooruPost) {
        guard let index = model.posts.firstIndex(where: { $0.globalID == post.globalID }) else { return }

        if index % BrowseViewModel.pageSize == 0 {
            model.setVisiblePage(model.pageNumber(forPostAt: index))
        }
        if index >= model.posts.count - 8 {
            Task { await model.loadMorePosts() }
        }
    }

    private func scrollToPost(_ postID: String, using proxy: ScrollViewProxy) {
        guard !suppressGridScroll else { return }
        guard model.posts.contains(where: { $0.globalID == postID }) else { return }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !suppressGridScroll else { return }
            proxy.scrollTo(postID, anchor: .top)
        }
    }

    private var loadingTitle: String {
        model.mode == .favorites ? "Loading favorites…" : "Loading posts…"
    }

    private var emptyStateTitle: String {
        model.mode == .favorites ? "No Favorites" : "No Posts"
    }

    private var emptyStateIcon: String {
        model.mode == .favorites ? "heart" : "photo.on.rectangle.angled"
    }

    private var emptyStateDescription: String {
        if model.mode == .favorites {
            return "Add posts to favorites from the gallery or preview."
        }
        return model.tagQuery.isEmpty
            ? "Try searching with tags."
            : "No results for these tags."
    }

    private func openGallery(post: BooruPost) {
        peek.dismiss()
        scrollRequest = post.globalID
        RemoteImageLoaderBridge.prefetch(post.viewerURL, priority: .high, maxPixelSize: nil)
        withAnimation(.easeInOut(duration: 0.25)) {
            gallery.open(model: model, postID: post.globalID)
        }
    }

    private func openPeek(for post: BooruPost) {
        guard let index = model.posts.firstIndex(where: { $0.globalID == post.globalID }) else { return }
        peek.open(model: model, at: index)
    }
}

private struct PostThumbnailCell: View {
    let post: BooruPost
    var tileWidth: CGFloat?
    var borderColor: Color?
    var upgradesToViewer = false
    let onTap: () -> Void
    let onLongPress: () -> Void

    var body: some View {
        Group {
            if let tileWidth {
                cellContent
                    .frame(width: tileWidth, alignment: .leading)
            } else {
                cellContent
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .onLongPressGesture(minimumDuration: 0.45, perform: onLongPress)
    }

    private var cellContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressiveRemoteImage(
                previewURL: post.previewURL,
                viewerURL: post.viewerURL,
                upgradesToViewer: upgradesToViewer,
                contentMode: .fit
            )
            .aspectRatio(post.aspectRatio, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                if let borderColor {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(borderColor, lineWidth: 2)
                }
            }

            HStack {
                Text("#\(post.id)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(post.score)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Masonry columns are expensive (O(posts × columns)). Equatable skips recompute when
/// the post list identity and width bucket are unchanged — critical on wide Mac windows.
private struct ColumnsMasonryGallery: View, Equatable {
    let posts: [BooruPost]
    let listGeneration: Int
    let contentWidth: CGFloat
    /// Invalidates the equatable cache when multi-server borders appear/disappear.
    let borderSignature: Int
    var upgradesToViewer = false
    let borderColorProvider: (BooruPost) -> Color?
    let onTap: (BooruPost) -> Void
    let onLongPress: (BooruPost) -> Void
    let onAppearPost: (BooruPost) -> Void

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.listGeneration == rhs.listGeneration
            && lhs.posts.count == rhs.posts.count
            && lhs.posts.last?.globalID == rhs.posts.last?.globalID
            && lhs.borderSignature == rhs.borderSignature
            && lhs.upgradesToViewer == rhs.upgradesToViewer
            && Int(lhs.contentWidth * 2) == Int(rhs.contentWidth * 2)
    }

    var body: some View {
        let layoutWidth = max(contentWidth, GalleryLayoutMetrics.minTileWidth)
        let columnCount = GalleryLayoutEngine.columnCount(for: layoutWidth)
        let columnWidth = GalleryLayoutEngine.columnWidth(for: layoutWidth, columnCount: columnCount)
        let gridWidth = GalleryLayoutEngine.gridWidth(columnCount: columnCount, columnWidth: columnWidth)
        let columns = GalleryLayoutEngine.masonryColumns(
            posts: posts,
            columnCount: columnCount,
            columnWidth: columnWidth
        )

        HStack(alignment: .top, spacing: GalleryLayoutMetrics.spacing) {
            ForEach(Array(columns.enumerated()), id: \.offset) { _, column in
                LazyVStack(spacing: GalleryLayoutMetrics.spacing) {
                    ForEach(column) { item in
                        PostThumbnailCell(
                            post: item.post,
                            tileWidth: columnWidth,
                            borderColor: borderColorProvider(item.post),
                            upgradesToViewer: upgradesToViewer,
                            onTap: { onTap(item.post) },
                            onLongPress: { onLongPress(item.post) }
                        )
                        .id(item.post.globalID)
                        .onAppear { onAppearPost(item.post) }
                    }
                }
                .frame(width: columnWidth, alignment: .top)
            }
        }
        .frame(width: gridWidth, alignment: .topLeading)
    }
}

#Preview {
    @Previewable @State var column: NavigationSplitViewColumn = .detail

    PostResultsView(
        model: BrowseViewModel(site: BooruSiteFactory.previewSite),
        preferredCompactColumn: $column,
        tilingMode: .adaptive
    )
    .environment(GalleryCoordinator())
    .environment(PeekCoordinator())
    .environment(ServerStore.shared)
}
