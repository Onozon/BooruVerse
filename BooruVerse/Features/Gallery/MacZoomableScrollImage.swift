#if os(macOS)
import AppKit
import SwiftUI

/// Native macOS zoom/pan via `NSScrollView.allowsMagnification` (trackpad pinch).
/// Centering uses a custom `NSClipView` — never call `scroll(to:)` during live magnify.
struct MacZoomableScrollImage: NSViewRepresentable {
    let image: PlatformImage?
    var isActive: Bool = true
    var onZoomChanged: ((Bool) -> Void)?
    var onTap: (() -> Void)?
    var onRequestFullImage: (() -> Void)?
    /// Return `true` if the vertical swipe was handled (dismiss). Only used at 1x.
    var onVerticalDismissScroll: ((NSEvent) -> Bool)?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> GalleryScrollView {
        let clipView = CenteringClipView()
        clipView.drawsBackground = true
        clipView.backgroundColor = .black

        let scrollView = GalleryScrollView()
        scrollView.contentView = clipView
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .black
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 1
        scrollView.maxMagnification = 5
        scrollView.magnification = 1
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets()
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .automatic

        let imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.wantsLayer = true
        imageView.layer?.backgroundColor = NSColor.black.cgColor
        scrollView.documentView = imageView

        context.coordinator.scrollView = scrollView
        context.coordinator.imageView = imageView
        context.coordinator.onZoomChanged = onZoomChanged
        context.coordinator.onTap = onTap
        context.coordinator.onRequestFullImage = onRequestFullImage
        context.coordinator.onVerticalDismissScroll = onVerticalDismissScroll

        scrollView.onMagnificationChange = { [weak coordinator = context.coordinator] mag in
            coordinator?.handleMagnification(mag)
        }
        scrollView.onPrimaryClick = { [weak coordinator = context.coordinator] clickCount in
            if clickCount >= 2 {
                coordinator?.handleDoubleClick()
            } else {
                coordinator?.handleClick()
            }
        }
        scrollView.onLayoutFinished = { [weak coordinator = context.coordinator] in
            coordinator?.relayoutDocumentIfNeeded()
        }
        scrollView.onScrollWheel = { [weak coordinator = context.coordinator] event in
            coordinator?.handleScrollWheel(event) ?? false
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.magnifyEnded(_:)),
            name: NSScrollView.didEndLiveMagnifyNotification,
            object: scrollView
        )

        return scrollView
    }

    func updateNSView(_ scrollView: GalleryScrollView, context: Context) {
        let coordinator = context.coordinator
        coordinator.onZoomChanged = onZoomChanged
        coordinator.onTap = onTap
        coordinator.onRequestFullImage = onRequestFullImage
        coordinator.onVerticalDismissScroll = onVerticalDismissScroll
        coordinator.apply(image: image)

        scrollView.verticalScrollElasticity = scrollView.magnification > 1.01 ? .automatic : .none

        if !isActive, scrollView.magnification > 1.01 {
            coordinator.resetZoom()
        }
    }

    static func dismantleNSView(_ nsView: GalleryScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        nsView.cancelPendingClick()
        nsView.onMagnificationChange = nil
        nsView.onPrimaryClick = nil
        nsView.onLayoutFinished = nil
        nsView.onScrollWheel = nil
        coordinator.invalidate()
    }

    final class Coordinator: NSObject {
        weak var scrollView: GalleryScrollView?
        weak var imageView: NSImageView?
        var onZoomChanged: ((Bool) -> Void)?
        var onTap: (() -> Void)?
        var onRequestFullImage: (() -> Void)?
        var onVerticalDismissScroll: ((NSEvent) -> Bool)?
        private var lastImage: NSImage?
        private var lastViewport: CGSize = .zero
        private var requestedFullImageForPinch = false
        private var isInvalidated = false

        func invalidate() {
            isInvalidated = true
            onZoomChanged = nil
            onTap = nil
            onRequestFullImage = nil
            onVerticalDismissScroll = nil
            scrollView = nil
            imageView = nil
        }

        func apply(image: PlatformImage?) {
            guard !isInvalidated, let scrollView, let imageView else { return }
            let changed = image !== lastImage
            guard changed || lastViewport == .zero else {
                relayoutDocumentIfNeeded(force: false)
                return
            }

            let preserveZoom = changed
                && scrollView.magnification > 1.01
                && image != nil
                && lastImage != nil

            if preserveZoom, let image {
                swapImagePreservingViewport(image)
                return
            }

            lastImage = image
            imageView.image = image

            if changed {
                scrollView.magnification = 1
                requestedFullImageForPinch = false
                lastViewport = .zero
                scrollView.verticalScrollElasticity = .none
                onZoomChanged?(false)
                relayoutDocumentIfNeeded(force: true)
            } else {
                relayoutDocumentIfNeeded(force: true)
            }
        }

        /// Replace bitmap without clearing pinch zoom or pan anchor.
        private func swapImagePreservingViewport(_ image: NSImage) {
            guard !isInvalidated, let scrollView, let imageView else { return }
            guard !scrollView.isLiveMagnifying else {
                lastImage = image
                imageView.image = image
                return
            }
            let clip = scrollView.contentView
            let oldSize = imageView.frame.size
            let oldBounds = clip.bounds
            let anchor = CGPoint(
                x: oldSize.width > 0.001 ? oldBounds.midX / oldSize.width : 0.5,
                y: oldSize.height > 0.001 ? oldBounds.midY / oldSize.height : 0.5
            )

            lastImage = image
            imageView.image = image

            let viewport = scrollView.bounds.size
            guard viewport.width > 8, viewport.height > 8 else { return }
            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            let fit = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
            let fitted = NSSize(width: imageSize.width * fit, height: imageSize.height * fit)
            imageView.setFrameSize(fitted)
            imageView.setFrameOrigin(.zero)
            lastViewport = viewport

            // Keep current magnification; restore the same relative focal point.
            // Avoid scroll(to:) — it EXC_BAD_ACCESS during magnify / teardown.
            let newOrigin = NSPoint(
                x: anchor.x * fitted.width - oldBounds.width / 2,
                y: anchor.y * fitted.height - oldBounds.height / 2
            )
            clip.setBoundsOrigin(newOrigin)
            scrollView.verticalScrollElasticity = .automatic
            onZoomChanged?(true)
        }

        func relayoutDocumentIfNeeded(force: Bool = false) {
            guard !isInvalidated, let scrollView, let imageView else { return }
            guard !scrollView.isLiveMagnifying else { return }
            // Never refit while zoomed — that recenters and kills pan.
            guard scrollView.magnification <= 1.01 else { return }

            let viewport = scrollView.bounds.size
            guard viewport.width > 8, viewport.height > 8 else { return }

            let viewportChanged = abs(viewport.width - lastViewport.width) > 0.5
                || abs(viewport.height - lastViewport.height) > 0.5
            guard force || viewportChanged else { return }
            lastViewport = viewport

            guard let image = imageView.image else {
                imageView.frame = CGRect(origin: .zero, size: viewport)
                return
            }

            let imageSize = image.size
            guard imageSize.width > 0, imageSize.height > 0 else { return }

            let fit = min(viewport.width / imageSize.width, viewport.height / imageSize.height)
            let fitted = NSSize(width: imageSize.width * fit, height: imageSize.height * fit)
            imageView.setFrameSize(fitted)
            imageView.setFrameOrigin(.zero)
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        func handleScrollWheel(_ event: NSEvent) -> Bool {
            guard !isInvalidated, let scrollView else { return false }
            // At 1x, vertical trackpad swipes dismiss instead of rubber-banding.
            guard scrollView.magnification <= 1.01 else { return false }
            guard event.hasPreciseScrollingDeltas else { return false }
            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            guard abs(dy) > abs(dx) else { return false }
            return onVerticalDismissScroll?(event) ?? false
        }

        func handleMagnification(_ magnification: CGFloat) {
            guard !isInvalidated else { return }
            let zoomed = magnification > 1.01
            scrollView?.verticalScrollElasticity = zoomed ? .automatic : .none
            if zoomed, !requestedFullImageForPinch {
                requestedFullImageForPinch = true
                onRequestFullImage?()
            }
            onZoomChanged?(zoomed)
        }

        @objc func magnifyEnded(_ note: Notification) {
            guard !isInvalidated, let scrollView else { return }
            scrollView.isLiveMagnifying = false
            requestedFullImageForPinch = false
            if scrollView.magnification < 1.02 {
                scrollView.magnification = 1
                scrollView.verticalScrollElasticity = .none
                lastViewport = .zero
                relayoutDocumentIfNeeded(force: true)
                onZoomChanged?(false)
            } else {
                scrollView.verticalScrollElasticity = .automatic
                onZoomChanged?(true)
            }
        }

        func handleClick() {
            guard !isInvalidated, let scrollView else { return }
            guard scrollView.magnification <= 1.01 else { return }
            onTap?()
        }

        func handleDoubleClick() {
            guard !isInvalidated, let scrollView else { return }
            if scrollView.magnification > 1.01 {
                scrollView.magnification = 1
                scrollView.verticalScrollElasticity = .none
                lastViewport = .zero
                relayoutDocumentIfNeeded(force: true)
                onZoomChanged?(false)
            } else {
                onRequestFullImage?()
            }
        }

        func resetZoom() {
            guard !isInvalidated, let scrollView else { return }
            scrollView.magnification = 1
            scrollView.verticalScrollElasticity = .none
            requestedFullImageForPinch = false
            lastViewport = .zero
            relayoutDocumentIfNeeded(force: true)
            onZoomChanged?(false)
        }
    }

    final class CenteringClipView: NSClipView {
        override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
            var rect = super.constrainBoundsRect(proposedBounds)
            guard let documentView else { return rect }

            let doc = documentView.frame.size
            if rect.size.width > doc.width {
                rect.origin.x = doc.width / 2 - rect.size.width / 2
            }
            if rect.size.height > doc.height {
                rect.origin.y = doc.height / 2 - rect.size.height / 2
            }
            return rect
        }
    }

    final class GalleryScrollView: NSScrollView {
        var onMagnificationChange: ((CGFloat) -> Void)?
        var onPrimaryClick: ((Int) -> Void)?
        var onLayoutFinished: (() -> Void)?
        /// Return true to consume the event (no rubber-band / paging).
        var onScrollWheel: ((NSEvent) -> Bool)?
        var isLiveMagnifying = false
        private var pendingSingleClick: DispatchWorkItem?
        private var lastLaidOutSize: NSSize = .zero

        override func layout() {
            super.layout()
            if abs(bounds.width - lastLaidOutSize.width) > 0.5
                || abs(bounds.height - lastLaidOutSize.height) > 0.5 {
                lastLaidOutSize = bounds.size
                onLayoutFinished?()
            }
        }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            if abs(newSize.width - lastLaidOutSize.width) > 0.5
                || abs(newSize.height - lastLaidOutSize.height) > 0.5 {
                lastLaidOutSize = newSize
                onLayoutFinished?()
            }
        }

        override func scrollWheel(with event: NSEvent) {
            if onScrollWheel?(event) == true {
                return
            }
            super.scrollWheel(with: event)
        }

        override func magnify(with event: NSEvent) {
            isLiveMagnifying = true
            super.magnify(with: event)
            onMagnificationChange?(magnification)
        }

        override func mouseUp(with event: NSEvent) {
            super.mouseUp(with: event)
            if event.clickCount == 1 {
                let work = DispatchWorkItem { [weak self] in
                    self?.onPrimaryClick?(1)
                }
                pendingSingleClick = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22, execute: work)
            } else if event.clickCount >= 2 {
                cancelPendingClick()
                onPrimaryClick?(2)
            }
        }

        func cancelPendingClick() {
            pendingSingleClick?.cancel()
            pendingSingleClick = nil
        }
    }
}
#endif
