import SwiftUI

struct RemoteThumbnail: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var maxPixelSize: Int = RemoteImageLoaderDefaults.thumbnailPixelSize

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
        "\(url?.absoluteString ?? "nil")-\(maxPixelSize)"
    }

    private func load() async {
        failed = false
        image = nil

        guard let url else {
            failed = true
            return
        }

        if let cached = await RemoteImageLoaderBridge.cachedImage(for: url, maxPixelSize: maxPixelSize) {
            image = cached.swiftUIImage
            return
        }

        if let loaded = await RemoteImageLoaderBridge.load(
            url: url,
            priority: .visible,
            maxPixelSize: maxPixelSize
        ) {
            image = loaded.swiftUIImage
        } else {
            failed = true
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
