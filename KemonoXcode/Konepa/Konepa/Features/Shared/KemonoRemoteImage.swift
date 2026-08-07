import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
private typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
private typealias PlatformImage = NSImage
#endif

/// In-memory cache for downloaded kemono images.
final class KemonoImageCache: @unchecked Sendable {
    static let shared = KemonoImageCache()

    private let cache = NSCache<NSString, CacheBox>()

    private init() {
        cache.countLimit = 300
    }

    func image(for key: String) -> Image? {
        cache.object(forKey: key as NSString)?.image
    }

    func store(_ image: Image, for key: String) {
        cache.setObject(CacheBox(image: image), forKey: key as NSString)
    }

    private final class CacheBox: NSObject {
        let image: Image
        init(image: Image) { self.image = image }
    }
}

/// Loads kemono CDN images with Referer/cookie headers (`AsyncImage` does not).
struct KemonoRemoteImage: View {
    let urlString: String?
    var contentMode: ContentMode = .fill
    var resolution: KemonoImageResolution = .preview
    var onLoadInfo: ((Bool) -> Void)?

    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .modifier(ImageScaleModifier(contentMode: contentMode))
            } else if failed {
                Image(systemName: "photo")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: taskKey) {
            await load()
        }
    }

    private var taskKey: String {
        "\(urlString ?? "")|\(resolution)"
    }

    private func load() async {
        image = nil
        failed = false
        onLoadInfo?(false)

        guard let urlString else {
            failed = true
            return
        }

        let cacheKey = "\(resolution)|\(urlString)"
        if let cached = KemonoImageCache.shared.image(for: cacheKey) {
            image = cached
            return
        }

        guard let result = await KemonoImageDownloader.load(pathOrURL: urlString, resolution: resolution),
              let platformImage = PlatformImage(data: result.data) else {
            failed = true
            return
        }

        let swiftImage = platformImage.swiftUIImage
        KemonoImageCache.shared.store(swiftImage, for: cacheKey)
        image = swiftImage
        onLoadInfo?(result.usedPreviewFallback)
    }
}

private extension PlatformImage {
    var swiftUIImage: Image {
#if canImport(UIKit)
        Image(uiImage: self)
#else
        Image(nsImage: self)
#endif
    }
}

private struct ImageScaleModifier: ViewModifier {
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
