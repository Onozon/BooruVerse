import SwiftUI

struct PostGalleryViewer: View {
    @Bindable var model: BrowseViewModel
    let posts: [BooruPost]
    @Binding var selectedPostID: String
    /// Browse tag set for toggle + selected chip styling.
    @Bindable var browseModel: BrowseViewModel
    let onToggleTag: (String) async -> Void
    let onPostsUpdated: () -> Void
    let onDismiss: () -> Void

    @Environment(AppSettingsStore.self) private var settings
    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PostFamilyStore.self) private var families

    private var selectedIndex: Int {
        posts.firstIndex(where: { $0.globalID == selectedPostID }) ?? 0
    }

    private var selectedBrowseTags: Set<String> {
        Set(browseModel.tagQuery.tags)
    }

    @State private var pageIndex = 0
    @State private var isZoomed = false
    @State private var showChrome = false
    @State private var dismissBackgroundOpacity: CGFloat = 1
    @State private var fullImageProgress: Double?
    @State private var upgradedPostID: String?
    @State private var upgradedImage: PlatformImage?
    @State private var fullImageLoadTask: Task<Void, Never>?
    @State private var videoMuted = true
#if os(macOS)
    @FocusState private var galleryFocused: Bool
#endif

    private var currentPost: BooruPost? {
        guard posts.indices.contains(selectedIndex) else { return nil }
        return posts[selectedIndex]
    }

    private var tagGroups: [BooruTagGroup] {
        guard let currentPost else { return [] }
        return model.postTagGroups(for: currentPost)
    }

    private var currentFamily: [BooruPost] {
        guard let currentPost else { return [] }
        return families.cachedFamily(for: currentPost)
    }

    var body: some View {
        Group {
            if currentPost != nil {
                galleryContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
#if os(iOS)
        .statusBarHidden(true)
#endif
        .onDisappear {
            cancelFullImageLoad()
        }
        .onAppear {
            guard let currentPost else {
                onDismiss()
                return
            }
            pageIndex = selectedIndex
            dismissBackgroundOpacity = 1
            videoMuted = true
            if !currentPost.isVideo {
                RemoteImageLoaderBridge.prefetch(currentPost.viewerURL)
            }
            model.resolvePostTags(for: currentPost)
            requestFullQualityIfNeeded(for: currentPost)
            Task { await families.loadIfNeeded(post: currentPost) }
#if os(macOS)
            galleryFocused = true
#endif
        }
        .onChange(of: selectedPostID) { oldID, newID in
            guard oldID != newID else { return }
            let index = posts.firstIndex(where: { $0.globalID == newID }) ?? pageIndex
            if pageIndex != index {
                pageIndex = index
            }
            handlePageChange(to: newID)
        }
        .onChange(of: pageIndex) { _, newIndex in
            guard posts.indices.contains(newIndex) else { return }
            let id = posts[newIndex].globalID
            if selectedPostID != id {
                selectedPostID = id
            }
        }
        .onChange(of: posts.map(\.globalID)) { _, ids in
            if let index = ids.firstIndex(of: selectedPostID), pageIndex != index {
                pageIndex = index
            }
        }
        .animation(.easeInOut(duration: 0.25), value: showChrome)
#if os(macOS)
        .focusable()
        .focused($galleryFocused)
        .focusEffectDisabled()
#endif
#if os(macOS)
        .onMoveCommand { direction in
            switch direction {
            case .left: moveTo(offset: -1)
            case .right: moveTo(offset: 1)
            default: break
            }
        }
        .onExitCommand {
            onDismiss()
        }
#endif
    }

    private var galleryContent: some View {
        ZStack {
            Color.black
                .opacity(Double(dismissBackgroundOpacity))
                .ignoresSafeArea()

            platformPager

            if fullImageProgress != nil {
                fullImageProgressBar
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if let currentPost, currentPost.isVideo {
                VideoMuteButton(isMuted: $videoMuted)
                    .padding(.trailing, 16)
                    .padding(.bottom, showChrome ? 200 : 24)
            }
        }
        .overlay(alignment: .top) {
            if showChrome, currentFamily.count > 1, let currentPost {
                PostFamilyStrip(
                    posts: currentFamily,
                    selectedID: currentPost.globalID,
                    usesLightContent: true,
                    onSelect: { gallery.selectRelated($0) }
                )
                .background(.black.opacity(0.45))
                .padding(.top, 48)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .overlay(alignment: .topTrailing) {
            if showChrome {
                GalleryCloseButton(onClose: onDismiss)
            }
        }
            .overlay(alignment: .topLeading) {
            if SelectionStore.shared.showsCheckboxes, let currentPost {
                SelectionCheckboxButton(isOn: SelectionStore.shared.contains(currentPost)) {
                    SelectionStore.shared.toggle(currentPost)
                }
                .padding(.horizontal, 16)
                .safeAreaPadding(.top, 8)
            }
        }
        .overlay(alignment: .bottom) {
            if showChrome, let currentPost {
                GalleryBottomChrome(
                    model: model,
                    post: currentPost,
                    tagGroups: tagGroups,
                    selectedTags: selectedBrowseTags,
                    onToggleTag: { tag in
                        Task {
                            await onToggleTag(tag)
                        }
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    model.resolvePostTags(for: currentPost)
                }
            }
        }
    }

    @ViewBuilder
    private var platformPager: some View {
#if os(iOS)
        iosLazyPager
#elseif os(macOS)
        macPageController
#endif
    }

#if os(iOS)
    private var iosLazyPager: some View {
        LazyPager(data: posts, page: $pageIndex) { post in
            GalleryPageImage(
                post: post,
                imageOverride: upgradedPostID == post.globalID ? upgradedImage : nil,
                loadPriority: post.globalID == selectedPostID ? .high : .background,
                isActive: post.globalID == selectedPostID,
                isMuted: $videoMuted,
                onImageLoaded: {
                    guard post.globalID == selectedPostID else { return }
                    prefetchAdjacentImages(around: selectedIndex)
                }
            )
        }
        .zoomable(min: 1, max: 5)
        .settings { config in
            config.contentAspectRatio = { post in
                guard post.width > 0, post.height > 0 else { return 16 / 9 }
                return CGFloat(post.width) / CGFloat(post.height)
            }
        }
        .onDismiss(backgroundOpacity: $dismissBackgroundOpacity) {
            onDismiss()
        }
        .onTap {
            toggleChrome()
        }
        .onDoubleTap {
            if let currentPost, !currentPost.isVideo, !currentPost.prefersAnimatedOriginal {
                requestFullImage(for: currentPost)
            }
        }
        .onZoom { post, scale in
            let zoomed = scale > 1.01
            isZoomed = zoomed
            if zoomed {
                requestFullImage(for: post)
            }
        }
        .shouldLoadMore {
            Task {
                await model.loadMorePostsIfNeeded(nearPostID: selectedPostID)
                onPostsUpdated()
            }
        }
        .background(Color.black.opacity(dismissBackgroundOpacity))
        .ignoresSafeArea()
    }
#endif

#if os(macOS)
    private var macPageController: some View {
        MacGalleryPager(
            selectedPostID: $selectedPostID,
            posts: posts,
            isZoomed: isZoomed,
            autoLoadFullQuality: settings.loadFullQualityInViewer,
            isMuted: videoMuted,
            onVerticalDismiss: {
                guard !isZoomed else { return }
                onDismiss()
            },
            onKeyboardDismiss: {
                onDismiss()
            },
            onKeyboardMove: { delta in
                moveTo(offset: delta)
            },
            onToggleChrome: {
                toggleChrome()
            },
            onZoomChanged: { zoomed in
                isZoomed = zoomed
            },
            onImageLoaded: { postID in
                guard postID == selectedPostID else { return }
                prefetchAdjacentImages(around: selectedIndex)
            },
            onFullImageProgress: { postID, progress in
                guard postID == selectedPostID else { return }
                fullImageProgress = progress
            }
        ) { post, dismissScroll in
            MacGalleryPage(
                post: post,
                onVerticalDismissScroll: dismissScroll
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
    }
#endif

    private var fullImageProgressBar: some View {
        VStack(spacing: 0) {
            Spacer()
            ProgressView(value: fullImageProgress ?? 0)
                .progressViewStyle(.linear)
                .tint(.white)
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
        }
        .allowsHitTesting(false)
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showChrome.toggle()
        }
    }

    private func fittedImageSize(for currentPost: BooruPost, in size: CGSize) -> CGSize {
        guard currentPost.width > 0, currentPost.height > 0 else {
            return size
        }

        let imageAspect = CGFloat(currentPost.width) / CGFloat(currentPost.height)
        let containerAspect = size.width / max(size.height, 1)

        if imageAspect > containerAspect {
            let width = size.width
            return CGSize(width: width, height: width / imageAspect)
        } else {
            let height = size.height
            return CGSize(width: height * imageAspect, height: height)
        }
    }

    private func handlePageChange(to newPostID: String) {
        isZoomed = false
        videoMuted = true
        resetFullImageUpgradeState()

        guard let post = posts.first(where: { $0.globalID == newPostID }) else {
            onDismiss()
            return
        }

        model.resolvePostTags(for: post)
        requestFullQualityIfNeeded(for: post)
        Task { await families.loadIfNeeded(post: post) }

        Task {
            await model.loadMorePostsIfNeeded(nearPostID: post.globalID)
            onPostsUpdated()
        }
    }

    private func requestFullQualityIfNeeded(for post: BooruPost) {
        guard settings.loadFullQualityInViewer else { return }
#if os(iOS)
        requestFullImage(for: post)
#endif
        // macOS: MacGalleryPage handles auto-load via `autoLoadFullQuality`.
    }

    private func prefetchAdjacentImages(around index: Int) {
        for neighborIndex in [index - 1, index + 1] where posts.indices.contains(neighborIndex) {
            let neighbor = posts[neighborIndex]
            guard !neighbor.isVideo else { continue }
            RemoteImageLoaderBridge.prefetch(
                neighbor.viewerURL,
                priority: .visible
            )
        }
    }

    private func moveTo(offset delta: Int) {
        let next = selectedIndex + delta
        guard posts.indices.contains(next) else { return }
        isZoomed = false
        selectedPostID = posts[next].globalID
    }

    private func requestFullImage(for post: BooruPost) {
        guard !post.isVideo, !post.prefersAnimatedOriginal else { return }
        guard post.hasHigherQualityOriginal else { return }
        guard upgradedPostID != post.globalID else { return }
        guard fullImageProgress == nil else { return }
        guard let fileURL = post.fileURL else { return }

        fullImageLoadTask?.cancel()
        fullImageLoadTask = Task {
            if let cached = await RemoteImageLoaderBridge.cachedImage(for: fileURL) {
                guard !Task.isCancelled else { return }
                applyFullImageUpgrade(cached, for: post)
                return
            }

            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    fullImageProgress = 0
                }
            }

            let image = await RemoteImageLoaderBridge.load(url: fileURL, priority: .high) { progress in
                Task { @MainActor in
                    fullImageProgress = progress
                }
            }

            guard !Task.isCancelled else { return }

            if let image {
                applyFullImageUpgrade(image, for: post)
            } else {
                await MainActor.run {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        fullImageProgress = nil
                    }
                }
            }
        }
    }

    private func applyFullImageUpgrade(_ image: PlatformImage, for post: BooruPost) {
        upgradedPostID = post.globalID
        upgradedImage = image
        fullImageProgress = nil
    }

    private func resetFullImageUpgradeState() {
        cancelFullImageLoad()
        upgradedPostID = nil
        upgradedImage = nil
    }

    private func cancelFullImageLoad() {
        fullImageLoadTask?.cancel()
        fullImageLoadTask = nil
        fullImageProgress = nil
    }
}
