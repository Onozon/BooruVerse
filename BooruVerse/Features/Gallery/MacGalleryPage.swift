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
    @State private var failed = false
    @State private var fullImageTask: Task<Void, Never>?

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
            if let displayImage {
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
                ContentUnavailableView("Image Unavailable", systemImage: "photo")
                    .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: post.viewerURL?.absoluteString ?? post.globalID) {
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

    private func load() async {
        failed = false
        localUpgradeImage = nil
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

    private func requestFullImage() {
        guard post.hasHigherQualityOriginal else { return }
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
