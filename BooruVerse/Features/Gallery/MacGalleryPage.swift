#if os(macOS)
import AppKit
import SwiftUI

/// Loads a post image and hosts it in a magnifying `NSScrollView`.
struct MacGalleryPage: View {
    let post: BooruPost
    var onVerticalDismissScroll: ((NSEvent) -> Bool)?

    @Environment(MacGallerySession.self) private var session
    @State private var platformImage: PlatformImage?
    @State private var localUpgradeImage: PlatformImage?
    @State private var animated: AnimatedImageDecoder.Decoded?
    @State private var failed = false
    @State private var fullImageTask: Task<Void, Never>?

    private var muteBinding: Binding<Bool> {
        Binding(
            get: { session.isMuted },
            set: { session.isMuted = $0 }
        )
    }

    private var isActive: Bool {
        session.isActive(post.globalID)
    }

    private var displayImage: PlatformImage? {
        localUpgradeImage ?? platformImage
    }

    private var loadPriority: RemoteImagePriority {
        isActive ? .high : .background
    }

    var body: some View {
        ZStack {
            Color.black
            mediaContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: post.playbackURL?.absoluteString ?? post.globalID) {
            await load()
        }
        .onChange(of: session.selectedPostID) { oldID, newID in
            if newID == post.globalID {
                if session.autoLoadFullQuality {
                    requestFullImage()
                }
            } else if oldID == post.globalID {
                cancelFullImageLoad()
            }
        }
        .onChange(of: session.autoLoadFullQuality) { _, enabled in
            if enabled, session.isActive(post.globalID) {
                requestFullImage()
            }
        }
        .onDisappear {
            cancelFullImageLoad()
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if post.isVideo, let url = post.playbackURL {
            GalleryVideoPlayer(
                url: url,
                usesNativePlayer: post.usesNativeAVPlayer,
                isActive: isActive,
                isMuted: muteBinding,
                showsMuteButton: false
            )
            .aspectRatio(post.aspectRatio, contentMode: .fit)
            .contentShape(Rectangle())
            .onTapGesture {
                guard isActive else { return }
                session.onToggleChrome?()
            }
        } else if let animated, animated.isAnimated {
            AnimatedFramesView(frames: animated.frames, durations: animated.durations, isActive: isActive)
                .contentShape(Rectangle())
                .onTapGesture {
                    guard isActive else { return }
                    session.onToggleChrome?()
                }
        } else if let displayImage {
            MacZoomableScrollImage(
                image: displayImage,
                isActive: isActive,
                onZoomChanged: { zoomed in
                    guard isActive else { return }
                    session.onZoomChanged?(zoomed)
                },
                onTap: {
                    guard isActive, !session.isZoomed else { return }
                    session.onToggleChrome?()
                },
                onRequestFullImage: { requestFullImage() },
                onVerticalDismissScroll: onVerticalDismissScroll
            )
        } else if failed {
            ContentUnavailableView("Image Unavailable", image: AppIcon.photo)
                .foregroundStyle(.white)
        } else {
            ProgressView()
                .tint(.white)
        }
    }

    private func load() async {
        failed = false
        localUpgradeImage = nil
        animated = nil
        guard !post.isVideo else { return }

        if post.prefersAnimatedOriginal, let url = post.playbackURL {
            await loadPossiblyAnimated(url: url)
            return
        }

        guard let url = post.viewerURL else {
            platformImage = nil
            failed = true
            return
        }

        if let cached = await RemoteImageLoaderBridge.cachedImage(for: url, maxPixelSize: nil) {
            platformImage = cached
            session.onImageLoaded?(post.globalID)
            if isActive, session.autoLoadFullQuality {
                requestFullImage()
            }
            return
        }
        if let preview = post.previewURL,
           let cachedPreview = await RemoteImageLoaderBridge.cachedImage(
            for: preview,
            maxPixelSize: RemoteImageLoaderBridge.defaultThumbnailPixelSize
           ) {
            platformImage = cachedPreview
            session.onImageLoaded?(post.globalID)
            if let full = await RemoteImageLoaderBridge.load(url: url, priority: loadPriority) {
                // In-place upgrade via representable update — zoom is preserved there.
                platformImage = full
            }
            if isActive, session.autoLoadFullQuality {
                requestFullImage()
            }
            return
        }

        guard let image = await RemoteImageLoaderBridge.load(url: url, priority: loadPriority) else {
            failed = platformImage == nil
            return
        }

        platformImage = image
        session.onImageLoaded?(post.globalID)
        if isActive, session.autoLoadFullQuality {
            requestFullImage()
        }
    }

    private func loadPossiblyAnimated(url: URL) async {
        if let preview = post.previewURL,
           let cachedPreview = await RemoteImageLoaderBridge.cachedImage(
            for: preview,
            maxPixelSize: RemoteImageLoaderBridge.defaultThumbnailPixelSize
           ) {
            platformImage = cachedPreview
            session.onImageLoaded?(post.globalID)
        }

        var request = URLRequest(url: url)
        request.setValue("BooruVerse/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 45

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
                failed = platformImage == nil
                return
            }
            guard let decoded = AnimatedImageDecoder.decode(data) else {
                failed = platformImage == nil
                return
            }
            if decoded.isAnimated {
                animated = decoded
            } else if let still = decoded.still {
                platformImage = still
            } else {
                failed = platformImage == nil
                return
            }
            session.onImageLoaded?(post.globalID)
        } catch {
            failed = platformImage == nil
        }
    }

    private func requestFullImage() {
        guard !post.isVideo, !post.prefersAnimatedOriginal else { return }
        guard localUpgradeImage == nil else { return }
        guard let fileURL = post.fileURL else { return }
        guard fullImageTask == nil else { return }

        fullImageTask = Task {
            if let cached = await RemoteImageLoaderBridge.cachedImage(for: fileURL) {
                guard !Task.isCancelled else { return }
                localUpgradeImage = cached
                if isActive {
                    session.onFullImageProgress?(post.globalID, nil)
                }
                fullImageTask = nil
                return
            }

            await MainActor.run {
                if isActive {
                    session.onFullImageProgress?(post.globalID, 0)
                }
            }

            let image = await RemoteImageLoaderBridge.load(url: fileURL, priority: .high) { progress in
                Task { @MainActor in
                    guard isActive else { return }
                    session.onFullImageProgress?(post.globalID, progress)
                }
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                if let image {
                    // Keep this local so MacGalleryPager doesn't rewrite the hosting tree
                    // (which remounted the scroll view and cleared pinch zoom).
                    localUpgradeImage = image
                }
                if isActive {
                    session.onFullImageProgress?(post.globalID, nil)
                }
                fullImageTask = nil
            }
        }
    }

    private func cancelFullImageLoad() {
        fullImageTask?.cancel()
        fullImageTask = nil
        if isActive {
            session.onFullImageProgress?(post.globalID, nil)
        }
    }
}
#endif
