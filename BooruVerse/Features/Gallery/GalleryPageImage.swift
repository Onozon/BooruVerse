import SwiftUI

/// Displays a post image without its own zoom/paging gestures.
/// Used inside LazyPager (iOS) / NSPageController (macOS) which own interaction.
struct GalleryPageImage: View {
    let post: BooruPost
    var imageOverride: PlatformImage?
    var fittedSize: CGSize?
    var loadPriority: RemoteImagePriority = .high
    var onImageLoaded: (() -> Void)?

    @State private var platformImage: PlatformImage?
    @State private var failed = false

    private var displayImage: PlatformImage? {
        imageOverride ?? platformImage
    }

    var body: some View {
        ZStack {
            Color.black
            if let displayImage {
                displayImage.swiftUIImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                ContentUnavailableView("Image Unavailable", systemImage: "photo")
                    .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .transaction { $0.animation = nil }
        .task(id: post.viewerURL?.absoluteString ?? post.globalID) {
            await load()
        }
    }

    private func load() async {
        failed = false
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

        if platformImage == nil {
            // keep previous frame while loading a new URL only when empty
        }

        guard let image = await RemoteImageLoaderBridge.load(url: url, priority: loadPriority) else {
            failed = true
            return
        }

        platformImage = image
        onImageLoaded?()
    }
}
