import SwiftUI
import UniformTypeIdentifiers

struct PostGalleryViewer: View {
    @Bindable var model: BrowseViewModel
    let posts: [BooruPost]
    @Binding var selectedPostID: String
    let onAddTag: (String) async -> Void
    let onPostsUpdated: () -> Void
    let onDismiss: () -> Void

    private var selectedIndex: Int {
        posts.firstIndex(where: { $0.globalID == selectedPostID }) ?? 0
    }

    @State private var dismissOffset: CGFloat = 0
    @State private var isZoomed = false
    @State private var showChrome = false
    @State private var exportDocument: SavedImageDocument?
    @State private var showFileExporter = false
    @State private var exportFilename = "image.jpg"
    @State private var exportContentType: UTType = .jpeg
    @State private var actionError: String?
    @State private var fullImageProgress: Double?
    @State private var upgradedPostID: String?
    @State private var upgradedImage: PlatformImage?
    @State private var fullImageLoadTask: Task<Void, Never>?
    @State private var isPagerReady = false
    @State private var suppressPagerScrollPosition = false

    private var currentPost: BooruPost? {
        guard posts.indices.contains(selectedIndex) else { return nil }
        return posts[selectedIndex]
    }

    private var tagGroups: [BooruTagGroup] {
        guard let currentPost else { return [] }
        return model.postTagGroups(for: currentPost)
    }

    private var dismissProgress: CGFloat {
        min(abs(dismissOffset) / 320, 1)
    }

    private var scrollPositionID: Binding<String?> {
        Binding(
            get: { selectedPostID },
            set: { newID in
                guard let newID, newID != selectedPostID else { return }
                selectedPostID = newID
            }
        )
    }

    var body: some View {
        Group {
            if currentPost != nil {
                galleryContent()
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
            isPagerReady = false
        }
        .onAppear {
            guard let currentPost else {
                onDismiss()
                return
            }
            RemoteImageLoaderBridge.prefetch(currentPost.viewerURL)
            model.resolvePostTags(for: currentPost)
        }
        .onChange(of: selectedPostID) { oldID, newID in
            guard oldID != newID else { return }
            handlePageChange(to: newID)
        }
        .animation(.easeInOut(duration: 0.25), value: showChrome)
        .simultaneousGesture(!isZoomed && !showChrome ? navigationGesture : nil)
        .fileExporter(
            isPresented: $showFileExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                actionError = error.localizedDescription
            }
        }
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
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

    @ViewBuilder
    private func galleryContent() -> some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .opacity(1 - Double(dismissProgress) * 0.5)
                    .ignoresSafeArea()
                    .onTapGesture {
                        if showChrome {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showChrome = false
                            }
                        } else {
                            onDismiss()
                        }
                    }

                imagePager(in: geometry)
                    .offset(y: dismissOffset)

                if fullImageProgress != nil {
                    fullImageProgressBar
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .topTrailing) {
                if showChrome {
                    GalleryCloseButton(onClose: onDismiss)
                }
            }
            .overlay(alignment: .bottom) {
                if showChrome, let currentPost {
                    GalleryBottomChrome(
                        model: model,
                        post: currentPost,
                        tagGroups: tagGroups,
                        onAddTag: { tag in
                            onDismiss()
                            Task {
                                await onAddTag(tag)
                            }
                        },
                        onExport: { Task { await prepareExport(for: currentPost) } },
                        onSaveError: { actionError = $0 }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        model.resolvePostTags(for: currentPost)
                    }
                }
            }
        }
    }

    private func imagePager(in geometry: GeometryProxy) -> some View {
        ScrollViewReader { proxy in
            let pager = ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(posts, id: \.globalID) { post in
                        imagePage(for: post, in: geometry)
                            .containerRelativeFrame(.horizontal)
                            .frame(height: geometry.size.height)
                            .id(post.globalID)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollDisabled(isZoomed)
            .background(Color.black)

            Group {
                if isPagerReady, !suppressPagerScrollPosition {
                    pager.scrollPosition(id: scrollPositionID)
                } else {
                    pager
                }
            }
            .opacity(isPagerReady ? 1 : 0)
            .onAppear {
                alignPager(to: selectedPostID, using: proxy, animated: false)
                DispatchQueue.main.async {
                    isPagerReady = true
                }
            }
            .onChange(of: geometry.size) { oldSize, newSize in
                guard oldSize != .zero, oldSize != newSize else { return }
                suppressPagerScrollPosition = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    alignPager(to: selectedPostID, using: proxy, animated: false)
                    suppressPagerScrollPosition = false
                }
            }
        }
    }

    private func alignPager(to postID: String, using proxy: ScrollViewProxy, animated: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = !animated
        withTransaction(transaction) {
            proxy.scrollTo(postID, anchor: .center)
        }
    }

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

    @ViewBuilder
    private func imagePage(
        for post: BooruPost,
        in geometry: GeometryProxy
    ) -> some View {
        let isCurrent = post.globalID == selectedPostID
        let fittedSize = fittedImageSize(for: post, in: geometry.size)

        ZoomableImageView(
            url: post.viewerURL,
            imageOverride: upgradedPostID == post.globalID ? upgradedImage : nil,
            fittedSize: fittedSize,
            viewportSize: geometry.size,
            loadPriority: isCurrent ? .high : .background,
            onZoomChanged: { zoomed in
                guard isCurrent else { return }
                Task { @MainActor in
                    isZoomed = zoomed
                }
            },
            onImageLoaded: {
                guard post.globalID == selectedPostID else { return }
                prefetchAdjacentImages(around: selectedIndex)
            },
            onTap: isCurrent && !isZoomed
                ? { toggleChrome() }
                : nil,
            onRequestFullImage: isCurrent
                ? { requestFullImage(for: post) }
                : nil
        )
        .frame(width: geometry.size.width, height: geometry.size.height)
        .allowsHitTesting(isCurrent)
    }

    private func toggleChrome() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showChrome.toggle()
        }
    }

    private var navigationGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                let vertical = value.translation.height
                let horizontal = value.translation.width
                guard abs(vertical) > abs(horizontal), vertical > 0 else { return }

                dismissOffset = vertical
            }
            .onEnded { value in
                let vertical = value.translation.height
                let horizontal = value.translation.width
                let isVertical = abs(vertical) > abs(horizontal)

                guard isVertical, vertical > 0 else {
                    dismissOffset = 0
                    return
                }

                let shouldDismiss = vertical > 120
                    || value.predictedEndTranslation.height > 200
                if shouldDismiss {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        dismissOffset = 0
                    }
                }
            }
    }

    private func prepareExport(for currentPost: BooruPost) async {
        do {
            exportDocument = try await model.exportDocument(for: currentPost)
            exportFilename = PostImageSaver.defaultFilename(for: currentPost)
            exportContentType = PostImageSaver.contentType(for: currentPost)
            showFileExporter = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func fittedImageSize(for currentPost: BooruPost, in size: CGSize) -> CGSize {
        guard currentPost.width > 0, currentPost.height > 0 else {
            return size
        }

        let imageAspect = CGFloat(currentPost.width) / CGFloat(currentPost.height)
        let containerAspect = size.width / size.height

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
        resetFullImageUpgradeState()

        guard let post = posts.first(where: { $0.globalID == newPostID }) else {
            onDismiss()
            return
        }

        model.resolvePostTags(for: post)

        Task {
            await model.loadMorePostsIfNeeded(nearPostID: post.globalID)
            onPostsUpdated()
        }
    }

    private func prefetchAdjacentImages(around index: Int) {
        for neighborIndex in [index - 1, index + 1] where posts.indices.contains(neighborIndex) {
            RemoteImageLoaderBridge.prefetch(
                posts[neighborIndex].viewerURL,
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
                    actionError = PostImageSaverError.missingImage.localizedDescription
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
