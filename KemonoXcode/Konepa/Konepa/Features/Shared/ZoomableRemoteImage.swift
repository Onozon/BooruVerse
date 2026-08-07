import SwiftUI

#if canImport(UIKit)
import UIKit

struct ZoomableRemoteImage: View {
    let path: String
    var resolution: KemonoImageResolution = .full
    var onPreviewFallback: ((Bool) -> Void)?

    @State private var uiImage: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let uiImage {
                ZoomableScrollView(image: uiImage)
            } else if failed {
                ContentUnavailableView("Image Unavailable", systemImage: "photo")
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(path)|\(resolution)") {
            await load()
        }
    }

    private func load() async {
        uiImage = nil
        failed = false
        onPreviewFallback?(false)

        guard let result = await KemonoImageDownloader.load(pathOrURL: path, resolution: resolution),
              let image = UIImage(data: result.data) else {
            failed = true
            return
        }

        uiImage = image
        onPreviewFallback?(result.usedPreviewFallback)
    }
}

private struct ZoomableScrollView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.backgroundColor = .black
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        guard let imageView = context.coordinator.imageView else { return }
        imageView.image = image
        context.coordinator.layoutImage(in: scrollView)
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidLayoutSubviews(_ scrollView: UIScrollView) {
            layoutImage(in: scrollView)
        }

        func layoutImage(in scrollView: UIScrollView) {
            guard let imageView, let image = imageView.image else { return }

            let bounds = scrollView.bounds.size
            guard bounds.width > 0, bounds.height > 0 else { return }

            let widthScale = bounds.width / image.size.width
            let heightScale = bounds.height / image.size.height
            let scale = min(widthScale, heightScale)

            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            imageView.frame = CGRect(
                x: (bounds.width - size.width) / 2,
                y: (bounds.height - size.height) / 2,
                width: size.width,
                height: size.height
            )
            scrollView.contentSize = bounds
            scrollView.zoomScale = 1
        }
    }
}
#else
import AppKit

struct ZoomableRemoteImage: View {
    let path: String
    var resolution: KemonoImageResolution = .full
    var onPreviewFallback: ((Bool) -> Void)?

    @State private var scale: CGFloat = 1
    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(MagnificationGesture().onChanged { value in
                        scale = max(1, min(value, 5))
                    })
            } else if failed {
                ContentUnavailableView("Image Unavailable", systemImage: "photo")
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(path)|\(resolution)") {
            await load()
        }
    }

    private func load() async {
        image = nil
        failed = false
        onPreviewFallback?(false)

        guard let result = await KemonoImageDownloader.load(pathOrURL: path, resolution: resolution),
              let nsImage = NSImage(data: result.data) else {
            failed = true
            return
        }

        image = Image(nsImage: nsImage)
        onPreviewFallback?(result.usedPreviewFallback)
    }
}
#endif
