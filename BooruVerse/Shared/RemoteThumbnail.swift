import SwiftUI

struct RemoteThumbnail: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    /// `nil` decodes at full resolution (viewer/sample quality). Default is feed-thumb size.
    var maxPixelSize: Int? = RemoteImageLoaderDefaults.thumbnailPixelSize

    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        GeometryReader { proxy in
            // Skip committing the decoded bitmap into a zero-sized layer (happens during
            // navigation pop / interactive back), which otherwise spams
            // "Failed to create WxH image slot" CoreAnimation errors.
            let hasValidSize = proxy.size.width > 1 && proxy.size.height > 1

            ZStack {
                Color.gray.opacity(0.12)

                if let image, hasValidSize {
                    image
                        .resizable()
                        .modifier(ThumbnailScaleMode(contentMode: contentMode))
                } else if failed {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: loadTaskID) {
            RemoteImageLoaderBridge.boostPriority(for: url, maxPixelSize: maxPixelSize)
            await load()
        }
    }

    private var loadTaskID: String {
        "\(url?.absoluteString ?? "nil")-\(maxPixelSize.map(String.init) ?? "full")"
    }

    private func load() async {
        failed = false

        guard let url else {
            image = nil
            failed = true
            return
        }

        if let cached = await RemoteImageLoaderBridge.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            image = cached.swiftUIImage
            return
        }

        // Don't clear an existing bitmap before fetch — LazyVStack recycle + task restart
        // otherwise flashes gray on every scroll pass.
        if let loaded = await RemoteImageLoaderBridge.load(
            url: url,
            priority: .visible,
            maxPixelSize: maxPixelSize
        ) {
            image = loaded.swiftUIImage
        } else if image == nil {
            failed = true
        }
    }
}

/// Compact gallery: show preview immediately, then upgrade on-screen cells to a capped feed-full size.
/// Scrolling away cancels the in-flight upgrade (preview stays).
struct ProgressiveRemoteImage: View {
    let previewURL: URL?
    let viewerURL: URL?
    var upgradesToViewer = false
    var contentMode: ContentMode = .fit
    var previewMaxPixelSize: Int? = RemoteImageLoaderDefaults.thumbnailPixelSize
    /// Decode cap for compact-feed upgrades (not true original / gallery full-res).
    var feedFullMaxPixelSize: Int? = RemoteImageLoaderDefaults.feedFullPixelSize

    @State private var image: Image?
    @State private var failed = false
    @State private var hasViewerQuality = false

    var body: some View {
        GeometryReader { proxy in
            let hasValidSize = proxy.size.width > 1 && proxy.size.height > 1

            ZStack {
                Color.gray.opacity(0.12)

                if let image, hasValidSize {
                    image
                        .resizable()
                        .modifier(ThumbnailScaleMode(contentMode: contentMode))
                } else if failed {
                    Image(systemName: "photo")
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .task(id: loadTaskID) {
            await loadPipeline()
        }
    }

    private var loadTaskID: String {
        let preview = previewURL?.absoluteString ?? "nil"
        let viewer = viewerURL?.absoluteString ?? "nil"
        return "\(preview)|\(viewer)|upgrade=\(upgradesToViewer)|full=\(feedFullMaxPixelSize.map(String.init) ?? "nil")"
    }

    private func loadPipeline() async {
        failed = false
        hasViewerQuality = false

        // Prefer cached feed-full quality when reappearing on screen.
        if upgradesToViewer,
           let viewerURL,
           let cachedViewer = await RemoteImageLoaderBridge.cachedImage(
               for: viewerURL,
               maxPixelSize: feedFullMaxPixelSize
           )
        {
            image = cachedViewer.swiftUIImage
            hasViewerQuality = true
            return
        }

        let previewOK = await loadPreview()
        guard !Task.isCancelled else { return }
        // Only upgrade after a successful preview — avoids racing full-quality on fast networks
        // while the user is still scrolling past unloaded cells.
        guard upgradesToViewer, previewOK else { return }

        await loadViewerUpgrade()
    }

    @discardableResult
    private func loadPreview() async -> Bool {
        guard let previewURL else {
            if image == nil { failed = true }
            return false
        }

        if let cached = await RemoteImageLoaderBridge.cachedImage(
            for: previewURL,
            maxPixelSize: previewMaxPixelSize
        ) {
            if !hasViewerQuality {
                image = cached.swiftUIImage
            }
            return true
        }

        RemoteImageLoaderBridge.boostPriority(for: previewURL, maxPixelSize: previewMaxPixelSize)
        if let loaded = await RemoteImageLoaderBridge.load(
            url: previewURL,
            priority: .visible,
            maxPixelSize: previewMaxPixelSize
        ) {
            if !hasViewerQuality {
                image = loaded.swiftUIImage
            }
            return true
        }

        if image == nil {
            failed = true
        }
        return false
    }

    private func loadViewerUpgrade() async {
        guard let viewerURL else { return }
        if viewerURL == previewURL {
            return
        }

        if let cached = await RemoteImageLoaderBridge.cachedImage(
            for: viewerURL,
            maxPixelSize: feedFullMaxPixelSize
        ) {
            image = cached.swiftUIImage
            hasViewerQuality = true
            return
        }

        RemoteImageLoaderBridge.boostPriority(for: viewerURL, maxPixelSize: feedFullMaxPixelSize)
        // Cancelling this task (cell scrolled off) cancels the upgrade when no other waiter remains.
        if let loaded = await RemoteImageLoaderBridge.load(
            url: viewerURL,
            priority: .visible,
            maxPixelSize: feedFullMaxPixelSize
        ) {
            guard !Task.isCancelled else { return }
            image = loaded.swiftUIImage
            hasViewerQuality = true
        }
    }
}

private struct ThumbnailScaleMode: ViewModifier {
    let contentMode: ContentMode

    func body(content: Content) -> some View {
        switch contentMode {
        case .fill:
            content.scaledToFill()
        case .fit:
            content.scaledToFit()
        @unknown default:
            content.scaledToFill()
        }
    }
}
