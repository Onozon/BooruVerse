import SwiftUI

struct ZoomableImageView: View {
    let url: URL?
    var imageOverride: PlatformImage?
    var fittedSize: CGSize?
    var viewportSize: CGSize?
    var loadPriority: RemoteImagePriority = .high
    var onZoomChanged: ((Bool) -> Void)?
    var onImageLoaded: (() -> Void)?
    var onTap: (() -> Void)?
    var onRequestFullImage: (() -> Void)?

    @State private var platformImage: PlatformImage?
    @State private var failed = false

    private var displayImage: PlatformImage? {
        imageOverride ?? platformImage
    }

#if !canImport(UIKit)
    @State private var requestedFullImageForCurrentPinch = false
    @State private var scale: CGFloat = 1
    @State private var steadyScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var steadyOffset: CGSize = .zero
    @State private var lastContentSize: CGSize = .zero
#endif

    var body: some View {
        GeometryReader { geometry in
            let viewport = resolvedViewport(in: geometry.size)
            let content = fittedSize ?? viewport

            ZStack {
#if canImport(UIKit)
                ZoomableScrollImageView(
                    image: displayImage,
                    viewportSize: viewport,
                    onZoomChanged: onZoomChanged,
                    onTap: onTap,
                    onRequestFullImage: onRequestFullImage
                )

                if failed, displayImage == nil {
                    unavailableView
                }
#else
                Color.clear
                    .frame(width: viewport.width, height: viewport.height)
                    .overlay {
                        if let displayImage {
                            displayImage.swiftUIImage
                                .resizable()
                                .scaledToFit()
                                .frame(width: content.width, height: content.height)
                                .scaleEffect(scale)
                                .offset(clampedOffset(viewportSize: viewport, contentSize: content))
                        }
                    }
                    .gesture(
                        zoomGesture(viewportSize: viewport, contentSize: content)
                            .simultaneously(with: panGesture(viewportSize: viewport, contentSize: content))
                    )
                    .overlay {
                        if failed, displayImage == nil {
                            unavailableView
                        }
                    }
                    .contentShape(Rectangle())
                    .highPriorityGesture(
                        TapGesture(count: 2).onEnded {
                            handleDoubleTap(viewportSize: viewport, contentSize: content)
                        }
                    )
                    .onTapGesture {
                        onTap?()
                    }
#endif
            }
            .frame(width: viewport.width, height: viewport.height)
            .onChange(of: viewport) { oldViewport, newViewport in
#if !canImport(UIKit)
                handleViewportChange(
                    from: oldViewport,
                    to: newViewport,
                    oldContent: lastContentSize,
                    newContent: content
                )
                lastContentSize = content
#endif
            }
            .onAppear {
#if !canImport(UIKit)
                lastContentSize = content
#endif
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: loadTaskID) {
            await load(priority: loadPriority)
        }
    }

    private var loadTaskID: String {
        "\(url?.absoluteString ?? "nil")-\(loadPriority.rawValue)"
    }

    private func resolvedViewport(in geometrySize: CGSize) -> CGSize {
        if let viewportSize, viewportSize.width > 0, viewportSize.height > 0 {
            return viewportSize
        }
        if let fittedSize, fittedSize.width > 0, fittedSize.height > 0 {
            return fittedSize
        }
        return geometrySize
    }

    private var unavailableView: some View {
        ContentUnavailableView("Image Unavailable", systemImage: "photo")
    }

#if !canImport(UIKit)
    private func zoomGesture(viewportSize: CGSize, contentSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let next = steadyScale * value
                let wasAtMinimum = steadyScale <= 1.01
                scale = min(max(next, 1), 5)
                if wasAtMinimum, scale > 1.01, !requestedFullImageForCurrentPinch {
                    requestedFullImageForCurrentPinch = true
                    onRequestFullImage?()
                }
                onZoomChanged?(scale > 1.01)
            }
            .onEnded { value in
                requestedFullImageForCurrentPinch = false
                let next = min(max(steadyScale * value, 1), 5)
                if next <= 1.02 {
                    resetTransform(animated: true)
                } else {
                    steadyScale = next
                    scale = next
                    applyClampedOffset(viewportSize: viewportSize, contentSize: contentSize, animated: true)
                    onZoomChanged?(true)
                }
            }
    }

    private func panGesture(viewportSize: CGSize, contentSize: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > 1.01 else { return }
                offset = clampedOffset(
                    viewportSize: viewportSize,
                    contentSize: contentSize,
                    proposed: CGSize(
                        width: steadyOffset.width + value.translation.width,
                        height: steadyOffset.height + value.translation.height
                    )
                )
            }
            .onEnded { _ in
                guard scale > 1.01 else { return }
                steadyOffset = clampedOffset(viewportSize: viewportSize, contentSize: contentSize, proposed: offset)
                offset = steadyOffset
            }
    }

    private func clampedOffset(
        viewportSize: CGSize,
        contentSize: CGSize,
        proposed: CGSize? = nil
    ) -> CGSize {
        guard scale > 1.001 else { return .zero }

        let source = proposed ?? offset
        let scaledWidth = contentSize.width * scale
        let scaledHeight = contentSize.height * scale
        let maxX = max(0, (scaledWidth - viewportSize.width) / 2)
        let maxY = max(0, (scaledHeight - viewportSize.height) / 2)

        return CGSize(
            width: min(max(source.width, -maxX), maxX),
            height: min(max(source.height, -maxY), maxY)
        )
    }

    private func applyClampedOffset(viewportSize: CGSize, contentSize: CGSize, animated: Bool) {
        let clamped = clampedOffset(viewportSize: viewportSize, contentSize: contentSize)
        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                offset = clamped
                steadyOffset = clamped
            }
        } else {
            offset = clamped
            steadyOffset = clamped
        }
    }

    private func handleViewportChange(
        from oldViewport: CGSize,
        to newViewport: CGSize,
        oldContent: CGSize,
        newContent: CGSize
    ) {
        guard oldViewport.width > 0, oldContent.width > 0, newContent.width > 0 else { return }
        guard oldViewport != newViewport else { return }

        if scale <= 1.01 {
            resetTransform(animated: false)
            return
        }

        let magnification = (oldContent.width * scale) / oldViewport.width
        let newScale = min(max((magnification * newViewport.width) / newContent.width, 1), 5)

        let imagePoint = CGPoint(
            x: 0.5 * oldContent.width - steadyOffset.width / scale,
            y: 0.5 * oldContent.height - steadyOffset.height / scale
        )
        let normalizedAnchor = CGPoint(
            x: imagePoint.x / oldContent.width,
            y: imagePoint.y / oldContent.height
        )
        let anchor = CGPoint(
            x: normalizedAnchor.x * newContent.width,
            y: normalizedAnchor.y * newContent.height
        )

        scale = newScale
        steadyScale = newScale
        let proposed = CGSize(
            width: (newContent.width / 2 - anchor.x) * newScale,
            height: (newContent.height / 2 - anchor.y) * newScale
        )
        offset = clampedOffset(viewportSize: newViewport, contentSize: newContent, proposed: proposed)
        steadyOffset = offset
        onZoomChanged?(true)
    }

    private func handleDoubleTap(viewportSize: CGSize, contentSize: CGSize) {
        if scale > 1.01 {
            resetTransform(animated: true)
        } else {
            onRequestFullImage?()
        }
    }
#endif

    private func resetTransform(animated: Bool) {
#if canImport(UIKit)
        onZoomChanged?(false)
#else
        let apply = {
            scale = 1
            steadyScale = 1
            offset = .zero
            steadyOffset = .zero
            onZoomChanged?(false)
        }

        if animated {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                apply()
            }
        } else {
            apply()
        }
#endif
    }

    private func load(priority: RemoteImagePriority) async {
        GalleryDebug.log("ZoomableImageView load start", url: url)
        failed = false
        resetTransform(animated: false)

        guard let url else {
            platformImage = nil
            failed = true
            GalleryDebug.log("ZoomableImageView no url")
            return
        }

        if let cached = await RemoteImageLoaderBridge.cachedImage(for: url) {
            GalleryDebug.log("ZoomableImageView cache hit", url: url)
            platformImage = cached
            onImageLoaded?()
            return
        }

        platformImage = nil

        guard let image = await RemoteImageLoaderBridge.load(url: url, priority: priority) else {
            GalleryDebug.log("ZoomableImageView load failed", url: url)
            failed = true
            return
        }

        GalleryDebug.log("ZoomableImageView load ok", url: url)
        platformImage = image
        onImageLoaded?()
    }
}

#if canImport(UIKit)
import UIKit

private struct ZoomableScrollImageView: UIViewRepresentable {
    let image: PlatformImage?
    let viewportSize: CGSize
    var onZoomChanged: ((Bool) -> Void)?
    var onTap: (() -> Void)?
    var onRequestFullImage: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 5
        scrollView.bounces = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.alwaysBounceVertical = false
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.backgroundColor = .clear
        scrollView.decelerationRate = .fast
        scrollView.clipsToBounds = true
        scrollView.isScrollEnabled = false

        let imageView = UIImageView()
        imageView.contentMode = .scaleAspectFit
        imageView.isHidden = true
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView
        context.coordinator.scrollView = scrollView

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.delegate = context.coordinator
        scrollView.addGestureRecognizer(tap)
        context.coordinator.tapRecognizer = tap

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap)
        )
        doubleTap.numberOfTapsRequired = 2
        doubleTap.delegate = context.coordinator
        scrollView.addGestureRecognizer(doubleTap)
        context.coordinator.doubleTapRecognizer = doubleTap
        tap.require(toFail: doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onZoomChanged = onZoomChanged
        coordinator.onTap = onTap
        coordinator.onRequestFullImage = onRequestFullImage

        let viewportChanged = coordinator.viewportSize != viewportSize
            && viewportSize.width > 0
            && viewportSize.height > 0
        coordinator.viewportSize = viewportSize

        coordinator.apply(image: image, in: scrollView)

        if viewportChanged {
            coordinator.scheduleRelayout(in: scrollView)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var onZoomChanged: ((Bool) -> Void)?
        var onTap: (() -> Void)?
        var onRequestFullImage: (() -> Void)?
        var viewportSize: CGSize = .zero
        weak var imageView: UIImageView?
        weak var scrollView: UIScrollView?
        weak var tapRecognizer: UITapGestureRecognizer?
        weak var doubleTapRecognizer: UITapGestureRecognizer?

        private var fittedImageSize: CGSize = .zero
        private var lastBounds: CGSize = .zero
        private weak var lastImage: UIImage?
        private var isProgrammaticLayout = false
        private var relayoutScheduled = false
        private var zoomScaleAtGestureStart: CGFloat?
        private var requestedFullImageForCurrentPinch = false

        func scheduleRelayout(in scrollView: UIScrollView) {
            guard !relayoutScheduled else { return }
            relayoutScheduled = true
            DispatchQueue.main.async { [weak self, weak scrollView] in
                guard let self, let scrollView else { return }
                self.relayoutScheduled = false
                self.layoutImage(in: scrollView, force: true)
            }
        }

        @objc func handleTap() {
            guard let scrollView else { return }
            guard scrollView.zoomScale <= scrollView.minimumZoomScale + 0.01 else { return }
            onTap?()
        }

        @objc func handleDoubleTap() {
            guard let scrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                onRequestFullImage?()
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func apply(image: UIImage?, in scrollView: UIScrollView) {
            guard let imageView else { return }

            let imageChanged = image !== lastImage
            if imageChanged {
                let previousImage = lastImage
                if let image,
                   canSwapImageInPlace(
                       from: previousImage,
                       to: image,
                       in: scrollView
                   ) {
                    swapImageInPlace(image, in: scrollView)
                    return
                }

                lastImage = image
                imageView.image = image
                imageView.isHidden = true
                performProgrammaticLayout {
                    scrollView.setZoomScale(1, animated: false)
                    scrollView.contentInset = .zero
                    scrollView.contentOffset = .zero
                }
                lastBounds = .zero
            }

            guard image != nil else {
                imageView.isHidden = true
                return
            }

            layoutImage(in: scrollView, force: imageChanged)
        }

        private func canSwapImageInPlace(
            from previousImage: UIImage?,
            to newImage: UIImage,
            in scrollView: UIScrollView
        ) -> Bool {
            guard let previousImage else { return false }
            guard imagesShareAspectRatio(previousImage, newImage) else { return false }
            guard fittedImageSize.width > 0, fittedImageSize.height > 0 else { return false }

            let bounds = scrollView.bounds.size
            guard bounds.width > 0, bounds.height > 0 else { return false }

            let newFittedSize = fittedSize(for: newImage, in: bounds)
            guard abs(newFittedSize.width - fittedImageSize.width) < 0.5,
                  abs(newFittedSize.height - fittedImageSize.height) < 0.5 else {
                return false
            }

            return true
        }

        private func swapImageInPlace(_ image: UIImage, in scrollView: UIScrollView) {
            guard let imageView else { return }

            lastImage = image
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            imageView.image = image
            CATransaction.commit()
            imageView.isHidden = false
            updateScrollEnabled(in: scrollView)
        }

        private func imagesShareAspectRatio(_ lhs: UIImage, _ rhs: UIImage) -> Bool {
            let lhsAspect = lhs.size.width / max(lhs.size.height, 1)
            let rhsAspect = rhs.size.width / max(rhs.size.height, 1)
            let maxAspect = max(lhsAspect, rhsAspect, 1)
            return abs(lhsAspect - rhsAspect) / maxAspect < 0.02
        }

        private func performProgrammaticLayout(_ updates: () -> Void) {
            isProgrammaticLayout = true
            updates()
            isProgrammaticLayout = false
        }

        private func notifyZoomChanged(_ zoomed: Bool) {
            DispatchQueue.main.async { [weak self] in
                self?.onZoomChanged?(zoomed)
            }
        }

        private func updateScrollEnabled(in scrollView: UIScrollView) {
            let zoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
            scrollView.isScrollEnabled = zoomed
        }

        func scrollViewDidLayoutSubviews(_ scrollView: UIScrollView) {
            guard !isProgrammaticLayout else { return }
            layoutImage(in: scrollView, force: false)
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
            zoomScaleAtGestureStart = scrollView.zoomScale
            requestedFullImageForCurrentPinch = false
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            guard !isProgrammaticLayout else { return }

            if scrollView.zoomScale < scrollView.minimumZoomScale {
                scrollView.zoomScale = scrollView.minimumZoomScale
            }

            let minimumScale = scrollView.minimumZoomScale
            if let startScale = zoomScaleAtGestureStart,
               startScale <= minimumScale + 0.01,
               scrollView.zoomScale > minimumScale + 0.01,
               !requestedFullImageForCurrentPinch {
                requestedFullImageForCurrentPinch = true
                onRequestFullImage?()
            }

            updateCentering(in: scrollView)
            clampContentOffset(in: scrollView)
            updateScrollEnabled(in: scrollView)
            notifyZoomChanged(scrollView.zoomScale > minimumScale + 0.01)
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isProgrammaticLayout else { return }
            guard scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 else { return }
            clampContentOffset(in: scrollView)
        }

        func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
            zoomScaleAtGestureStart = nil
            requestedFullImageForCurrentPinch = false

            let minimumScale = scrollView.minimumZoomScale
            if scale < minimumScale + 0.02 {
                performProgrammaticLayout {
                    guard let imageView, let image = imageView.image else { return }
                    scrollView.setZoomScale(minimumScale, animated: false)
                    applyMinimumZoomLayout(in: scrollView, image: image)
                }
                updateScrollEnabled(in: scrollView)
                notifyZoomChanged(false)
            } else {
                updateCentering(in: scrollView)
                clampContentOffset(in: scrollView)
                updateScrollEnabled(in: scrollView)
                notifyZoomChanged(true)
            }
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            guard !decelerate else { return }
            guard scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 else { return }
            clampContentOffset(in: scrollView)
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            guard scrollView.zoomScale > scrollView.minimumZoomScale + 0.01 else { return }
            clampContentOffset(in: scrollView)
        }

        private func fittedSize(for image: UIImage, in bounds: CGSize) -> CGSize {
            guard bounds.width > 0, bounds.height > 0 else { return .zero }

            let widthScale = bounds.width / image.size.width
            let heightScale = bounds.height / image.size.height
            let fitScale = min(widthScale, heightScale)
            return CGSize(
                width: image.size.width * fitScale,
                height: image.size.height * fitScale
            )
        }

        private func layoutImage(in scrollView: UIScrollView, force: Bool) {
            guard let imageView, let image = imageView.image else { return }

            let bounds = scrollView.bounds.size
            guard bounds.width > 0, bounds.height > 0 else { return }

            let boundsChanged = lastBounds.width > 0 && bounds != lastBounds
            let isZoomed = scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
            guard force || boundsChanged || imageView.isHidden else { return }

            let rotationAnchor: CGPoint?
            let preservedMagnification: CGFloat?
            if boundsChanged && isZoomed {
                let centerInScroll = CGPoint(x: scrollView.bounds.midX, y: scrollView.bounds.midY)
                let anchor = scrollView.convert(centerInScroll, to: imageView)
                let oldFitted = fittedImageSize
                rotationAnchor = CGPoint(
                    x: anchor.x / max(oldFitted.width, 1),
                    y: anchor.y / max(oldFitted.height, 1)
                )
                preservedMagnification = (oldFitted.width * scrollView.zoomScale) / lastBounds.width
            } else {
                rotationAnchor = nil
                preservedMagnification = nil
            }

            lastBounds = bounds
            let newFittedSize = fittedSize(for: image, in: bounds)

            performProgrammaticLayout {
                if let normalizedAnchor = rotationAnchor, let magnification = preservedMagnification {
                    fittedImageSize = newFittedSize
                    imageView.frame = CGRect(origin: .zero, size: newFittedSize)
                    scrollView.contentSize = newFittedSize
                    applyRotatedZoomLayout(
                        scrollView: scrollView,
                        normalizedAnchor: normalizedAnchor,
                        magnification: magnification,
                        bounds: bounds
                    )
                } else if isZoomed {
                    fittedImageSize = newFittedSize
                    imageView.frame = CGRect(origin: .zero, size: newFittedSize)
                    scrollView.contentSize = newFittedSize
                    updateCentering(in: scrollView)
                    clampContentOffset(in: scrollView)
                } else {
                    scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
                    applyMinimumZoomLayout(in: scrollView, image: image)
                }

                imageView.isHidden = false
            }

            updateScrollEnabled(in: scrollView)
        }

        private func applyMinimumZoomLayout(in scrollView: UIScrollView, image: UIImage) {
            guard let imageView else { return }

            let bounds = scrollView.bounds.size
            let fitted = fittedSize(for: image, in: bounds)
            fittedImageSize = fitted
            imageView.frame = CGRect(origin: .zero, size: fitted)
            scrollView.contentSize = fitted
            scrollView.contentInset = .zero
            updateCentering(in: scrollView)
            clampContentOffset(in: scrollView)
        }

        private func updateCentering(in scrollView: UIScrollView) {
            let bounds = scrollView.bounds.size
            guard bounds.width > 0, bounds.height > 0, fittedImageSize.width > 0 else { return }

            let zoom = scrollView.zoomScale
            let scaledWidth = fittedImageSize.width * zoom
            let scaledHeight = fittedImageSize.height * zoom
            let insetX = max((bounds.width - scaledWidth) / 2, 0)
            let insetY = max((bounds.height - scaledHeight) / 2, 0)

            scrollView.contentInset = UIEdgeInsets(
                top: insetY,
                left: insetX,
                bottom: insetY,
                right: insetX
            )

            if zoom <= scrollView.minimumZoomScale + 0.001 {
                scrollView.contentOffset = CGPoint(x: -insetX, y: -insetY)
            }
        }

        private func applyRotatedZoomLayout(
            scrollView: UIScrollView,
            normalizedAnchor: CGPoint,
            magnification: CGFloat,
            bounds: CGSize
        ) {
            var newZoomScale = (magnification * bounds.width) / max(fittedImageSize.width, 1)
            newZoomScale = min(max(newZoomScale, scrollView.minimumZoomScale), scrollView.maximumZoomScale)
            scrollView.setZoomScale(newZoomScale, animated: false)
            updateCentering(in: scrollView)

            let anchor = CGPoint(
                x: normalizedAnchor.x * fittedImageSize.width,
                y: normalizedAnchor.y * fittedImageSize.height
            )
            scrollView.contentOffset = CGPoint(
                x: anchor.x * newZoomScale - bounds.width / 2,
                y: anchor.y * newZoomScale - bounds.height / 2
            )
            clampContentOffset(in: scrollView)
        }

        private func clampContentOffset(in scrollView: UIScrollView) {
            let bounds = scrollView.bounds.size
            let inset = scrollView.contentInset
            let zoom = scrollView.zoomScale
            let scaledWidth = fittedImageSize.width * zoom
            let scaledHeight = fittedImageSize.height * zoom

            if zoom <= scrollView.minimumZoomScale + 0.001 {
                let centered = CGPoint(x: -inset.left, y: -inset.top)
                if scrollView.contentOffset != centered {
                    scrollView.contentOffset = centered
                }
                return
            }

            let minX = -inset.left
            let minY = -inset.top
            let maxX = max(minX, scaledWidth - bounds.width + inset.right)
            let maxY = max(minY, scaledHeight - bounds.height + inset.bottom)

            var offset = scrollView.contentOffset
            offset.x = min(max(offset.x, minX), maxX)
            offset.y = min(max(offset.y, minY), maxY)

            if offset != scrollView.contentOffset {
                scrollView.contentOffset = offset
            }
        }
    }
}
#endif
