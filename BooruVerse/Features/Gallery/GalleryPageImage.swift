import SwiftUI

/// Displays a post image without its own zoom/paging gestures.
/// Used inside LazyPager (iOS) / NSPageController (macOS) which own interaction.
struct GalleryPageImage: View {
    let post: BooruPost
    var imageOverride: PlatformImage?
    var fittedSize: CGSize?
    var loadPriority: RemoteImagePriority = .high
    var isActive: Bool = true
    @Binding var isMuted: Bool
    var showsMuteButton: Bool = false
    var onImageLoaded: (() -> Void)?

    @State private var platformImage: PlatformImage?
    @State private var animated: AnimatedImageDecoder.Decoded?
    @State private var failed = false

    private var displayImage: PlatformImage? {
        imageOverride ?? platformImage
    }

    var body: some View {
        ZStack {
            Color.black
            mediaContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { $0.animation = nil }
        .task(id: post.playbackURL?.absoluteString ?? post.globalID) {
            await load()
        }
    }

    @ViewBuilder
    private var mediaContent: some View {
        if post.isVideo, let url = post.playbackURL {
            GalleryVideoPlayer(
                url: url,
                usesNativePlayer: post.usesNativeAVPlayer,
                isActive: isActive,
                isMuted: $isMuted,
                showsMuteButton: showsMuteButton
            )
        } else if let animated, animated.isAnimated {
            AnimatedFramesView(frames: animated.frames, durations: animated.durations, isActive: isActive)
        } else if let displayImage {
            displayImage.swiftUIImage
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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

        if let cached = await RemoteImageLoaderBridge.cachedImage(for: url) {
            platformImage = cached
            onImageLoaded?()
            return
        }

        guard let image = await RemoteImageLoaderBridge.load(url: url, priority: loadPriority) else {
            failed = true
            return
        }

        platformImage = image
        onImageLoaded?()
    }

    private func loadPossiblyAnimated(url: URL) async {
        if let preview = post.previewURL,
           let cached = await RemoteImageLoaderBridge.cachedImage(
            for: preview,
            maxPixelSize: RemoteImageLoaderDefaults.thumbnailPixelSize
           ) {
            platformImage = cached
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
            onImageLoaded?()
        } catch {
            failed = platformImage == nil
        }
    }
}
