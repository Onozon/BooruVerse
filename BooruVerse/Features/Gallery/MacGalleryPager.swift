#if os(macOS)
import AppKit
import SwiftUI

/// Shared mutable gallery state for hosted pages.
/// Pages observe this instead of getting remounted via `NSHostingController.rootView`
/// on every selection change (that path was crashing AppKit scroll views).
@MainActor
@Observable
final class MacGallerySession {
    var selectedPostID: String
    var isZoomed = false
    var autoLoadFullQuality = false
    var onToggleChrome: (() -> Void)?
    var onZoomChanged: ((Bool) -> Void)?
    var onImageLoaded: ((String) -> Void)?
    var onFullImageProgress: ((String, Double?) -> Void)?

    init(selectedPostID: String) {
        self.selectedPostID = selectedPostID
    }

    func isActive(_ postID: String) -> Bool {
        selectedPostID == postID
    }
}

/// Trackpad-friendly gallery pager backed by `NSPageController`.
struct MacGalleryPager<Page: View>: NSViewControllerRepresentable {
    @Binding var selectedPostID: String
    let posts: [BooruPost]
    var isZoomed: Bool = false
    var autoLoadFullQuality: Bool = false
    var onVerticalDismiss: (() -> Void)?
    var onKeyboardDismiss: (() -> Void)?
    var onKeyboardMove: ((Int) -> Void)?
    var onToggleChrome: (() -> Void)?
    var onZoomChanged: ((Bool) -> Void)?
    var onImageLoaded: ((String) -> Void)?
    var onFullImageProgress: ((String, Double?) -> Void)?
    @ViewBuilder var pageContent: (BooruPost, @escaping (NSEvent) -> Bool) -> Page

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedPostID: $selectedPostID)
    }

    func makeNSViewController(context: Context) -> GalleryNSPageController {
        let controller = GalleryNSPageController()
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = NSColor.black.cgColor
        controller.transitionStyle = .horizontalStrip
        controller.delegate = context.coordinator
        controller.onVerticalDismissScroll = { [weak coordinator = context.coordinator] event in
            coordinator?.handleDismissScroll(event) ?? false
        }
        controller.onKeyboardDismiss = { [weak coordinator = context.coordinator] in
            coordinator?.onKeyboardDismiss?()
        }
        controller.onKeyboardMove = { [weak coordinator = context.coordinator] delta in
            coordinator?.onKeyboardMove?(delta)
        }
        context.coordinator.pageController = controller
        context.coordinator.syncCallbacks(
            onVerticalDismiss: onVerticalDismiss,
            onKeyboardDismiss: onKeyboardDismiss,
            onKeyboardMove: onKeyboardMove,
            onToggleChrome: onToggleChrome,
            onZoomChanged: onZoomChanged,
            onImageLoaded: onImageLoaded,
            onFullImageProgress: onFullImageProgress,
            isZoomed: isZoomed,
            autoLoadFullQuality: autoLoadFullQuality
        )
        context.coordinator.startKeyboardMonitor()
        DispatchQueue.main.async {
            context.coordinator.apply(
                posts: posts,
                selectedPostID: selectedPostID,
                pageContent: pageContent,
                forceContentRefresh: true
            )
            controller.claimKeyFocus()
        }
        return controller
    }

    func updateNSViewController(_ controller: GalleryNSPageController, context: Context) {
        context.coordinator.pageController = controller
        context.coordinator.syncCallbacks(
            onVerticalDismiss: onVerticalDismiss,
            onKeyboardDismiss: onKeyboardDismiss,
            onKeyboardMove: onKeyboardMove,
            onToggleChrome: onToggleChrome,
            onZoomChanged: onZoomChanged,
            onImageLoaded: onImageLoaded,
            onFullImageProgress: onFullImageProgress,
            isZoomed: isZoomed,
            autoLoadFullQuality: autoLoadFullQuality
        )
        controller.isZoomed = isZoomed
        controller.onVerticalDismissScroll = { [weak coordinator = context.coordinator] event in
            coordinator?.handleDismissScroll(event) ?? false
        }
        controller.onKeyboardDismiss = { [weak coordinator = context.coordinator] in
            coordinator?.onKeyboardDismiss?()
        }
        controller.onKeyboardMove = { [weak coordinator = context.coordinator] delta in
            coordinator?.onKeyboardMove?(delta)
        }
        context.coordinator.apply(
            posts: posts,
            selectedPostID: selectedPostID,
            pageContent: pageContent,
            forceContentRefresh: false
        )
    }

    static func dismantleNSViewController(_ controller: GalleryNSPageController, coordinator: Coordinator) {
        coordinator.stopKeyboardMonitor()
    }

    final class Coordinator: NSObject, NSPageControllerDelegate {
        var selectedPostID: Binding<String>
        weak var pageController: GalleryNSPageController?
        var onVerticalDismiss: (() -> Void)?
        var onKeyboardDismiss: (() -> Void)?
        var onKeyboardMove: ((Int) -> Void)?
        var isZoomed = false
        let session: MacGallerySession
        private var posts: [BooruPost] = []
        private var controllers: [String: NSHostingController<AnyView>] = [:]
        private var isApplyingSelection = false
        private var isLiveTransition = false
        private var pageContent: ((BooruPost, @escaping (NSEvent) -> Bool) -> Page)?
        private var dismissCarry: CGFloat = 0
        private var lastSelectedID: String?
        private var lastPostIDs: [String] = []
        private var keyboardMonitor: Any?
        private var pendingApply: PendingApply?

        private struct PendingApply {
            var posts: [BooruPost]
            var selectedPostID: String
            var pageContent: (BooruPost, @escaping (NSEvent) -> Bool) -> Page
            var forceContentRefresh: Bool
        }

        init(selectedPostID: Binding<String>) {
            self.selectedPostID = selectedPostID
            self.session = MacGallerySession(selectedPostID: selectedPostID.wrappedValue)
        }

        func syncCallbacks(
            onVerticalDismiss: (() -> Void)?,
            onKeyboardDismiss: (() -> Void)?,
            onKeyboardMove: ((Int) -> Void)?,
            onToggleChrome: (() -> Void)?,
            onZoomChanged: ((Bool) -> Void)?,
            onImageLoaded: ((String) -> Void)?,
            onFullImageProgress: ((String, Double?) -> Void)?,
            isZoomed: Bool,
            autoLoadFullQuality: Bool
        ) {
            self.onVerticalDismiss = onVerticalDismiss
            self.onKeyboardDismiss = onKeyboardDismiss
            self.onKeyboardMove = onKeyboardMove
            self.isZoomed = isZoomed
            session.isZoomed = isZoomed
            session.autoLoadFullQuality = autoLoadFullQuality
            session.onToggleChrome = onToggleChrome
            session.onZoomChanged = onZoomChanged
            session.onImageLoaded = onImageLoaded
            session.onFullImageProgress = onFullImageProgress
        }

        func startKeyboardMonitor() {
            guard keyboardMonitor == nil else { return }
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self else { return event }
                guard let pageController, event.window == pageController.view.window else {
                    return event
                }
                return self.handleKeyDown(event)
            }
        }

        func stopKeyboardMonitor() {
            if let keyboardMonitor {
                NSEvent.removeMonitor(keyboardMonitor)
            }
            keyboardMonitor = nil
        }

        private func handleKeyDown(_ event: NSEvent) -> NSEvent? {
            switch Int(event.keyCode) {
            case 53: // escape
                onKeyboardDismiss?()
                return nil
            case 123: // left arrow
                onKeyboardMove?(-1)
                return nil
            case 124: // right arrow
                onKeyboardMove?(1)
                return nil
            default:
                return event
            }
        }

        /// Shared by page-controller and per-page scroll views.
        func handleDismissScroll(_ event: NSEvent) -> Bool {
            guard !isZoomed else { return false }
            guard event.hasPreciseScrollingDeltas else { return false }

            let dx = event.scrollingDeltaX
            let dy = event.scrollingDeltaY
            let phaseEnded = event.phase == .ended || event.phase == .cancelled
                || event.momentumPhase == .ended || event.momentumPhase == .cancelled

            guard abs(dy) > abs(dx), abs(dy) > 0.2 else {
                if phaseEnded { dismissCarry = 0 }
                return false
            }

            // Accept either natural-scroll polarity so top→bottom always accumulates.
            dismissCarry += abs(dy)

            let shouldDismiss = dismissCarry > 55
                || (phaseEnded && dismissCarry > 28)
            if shouldDismiss {
                dismissCarry = 0
                // Gallery views go away immediately; keep eating this gesture so
                // residual trackpad motion doesn't scroll/refresh the feed below.
                TrackpadScrollLock.beginUntilScrollGestureEnds()
                onVerticalDismiss?()
                return true
            }
            if phaseEnded {
                dismissCarry = 0
            }
            // Consume vertical so NSPageController / NSScrollView don't spring-back.
            return true
        }

        func apply(
            posts: [BooruPost],
            selectedPostID: String,
            pageContent: @escaping (BooruPost, @escaping (NSEvent) -> Bool) -> Page,
            forceContentRefresh: Bool
        ) {
            // Never mutate arrangedObjects / hosting trees mid-swipe — AppKit can
            // EXC_BAD_ACCESS inside objc_msgSend when scroll views are remounted.
            if isLiveTransition {
                pendingApply = PendingApply(
                    posts: posts,
                    selectedPostID: selectedPostID,
                    pageContent: pageContent,
                    forceContentRefresh: forceContentRefresh
                )
                session.selectedPostID = selectedPostID
                return
            }

            self.pageContent = pageContent
            self.posts = posts
            session.selectedPostID = selectedPostID
            guard let pageController else { return }

            let bounds = pageController.view.bounds
            if bounds.width < 8 || bounds.height < 8 {
                DispatchQueue.main.async { [weak self] in
                    self?.apply(
                        posts: posts,
                        selectedPostID: selectedPostID,
                        pageContent: pageContent,
                        forceContentRefresh: true
                    )
                }
                return
            }

            if let superview = pageController.view.superview {
                pageController.view.frame = superview.bounds
            }
            pageController.view.autoresizingMask = [.width, .height]

            let ids = posts.map(\.globalID)
            if lastPostIDs != ids {
                let valid = Set(ids)
                controllers = controllers.filter { valid.contains($0.key) }
                pageController.arrangedObjects = ids
                lastPostIDs = ids
            }

            let selectionChanged = lastSelectedID != selectedPostID
            lastSelectedID = selectedPostID

            guard let index = posts.firstIndex(where: { $0.globalID == selectedPostID }) else { return }

            // Only rewrite hosting trees on first layout (or explicit force). Selection /
            // zoom / progress updates flow through `MacGallerySession` instead.
            if forceContentRefresh {
                for offset in -1...1 {
                    let i = index + offset
                    guard posts.indices.contains(i) else { continue }
                    updateHosting(for: posts[i])
                }
            }

            if pageController.selectedIndex != index {
                isApplyingSelection = true
                pageController.selectedIndex = index
                pageController.completeTransition()
                isApplyingSelection = false
            } else if forceContentRefresh {
                pageController.completeTransition()
            }

            if selectionChanged || forceContentRefresh {
                syncSelectedViewFrame()
            }
        }

        private func syncSelectedViewFrame() {
            guard let pageController else { return }
            let bounds = pageController.view.bounds
            guard bounds.width > 8, bounds.height > 8 else { return }

            if let selected = pageController.selectedViewController {
                selected.view.frame = bounds
                selected.view.autoresizingMask = [.width, .height]
                selected.view.layoutSubtreeIfNeeded()
            }
        }

        private func dismissScrollHandler() -> (NSEvent) -> Bool {
            { [weak self] event in
                self?.handleDismissScroll(event) ?? false
            }
        }

        private func wrappedPage(for post: BooruPost) -> AnyView {
            guard let pageContent else {
                return AnyView(Color.black)
            }
            return AnyView(
                pageContent(post, dismissScrollHandler())
                    .environment(session)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .ignoresSafeArea()
            )
        }

        private func updateHosting(for post: BooruPost) {
            guard let hosting = controllers[post.globalID] else { return }
            hosting.safeAreaRegions = []
            hosting.rootView = wrappedPage(for: post)
        }

        func pageController(
            _ pageController: NSPageController,
            identifierFor object: Any
        ) -> NSPageController.ObjectIdentifier {
            (object as? String) ?? ""
        }

        func pageController(
            _ pageController: NSPageController,
            viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier
        ) -> NSViewController {
            if let cached = controllers[identifier] {
                return cached
            }

            let post = posts.first(where: { $0.globalID == identifier })
            let root: AnyView
            if let post {
                root = wrappedPage(for: post)
            } else {
                root = AnyView(Color.black.environment(session))
            }

            let hosting = NSHostingController(rootView: root)
            hosting.safeAreaRegions = []
            hosting.view.wantsLayer = true
            hosting.view.layer?.backgroundColor = NSColor.black.cgColor
            hosting.view.autoresizingMask = [.width, .height]
            controllers[identifier] = hosting
            return hosting
        }

        func pageController(
            _ pageController: NSPageController,
            prepare viewController: NSViewController,
            with object: Any?
        ) {
            viewController.view.frame = pageController.view.bounds
            viewController.view.autoresizingMask = [.width, .height]
        }

        func pageControllerWillStartLiveTransition(_ pageController: NSPageController) {
            isLiveTransition = true
        }

        func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
            isLiveTransition = false
            pageController.completeTransition()
            syncSelectedViewFrame()
            (pageController as? GalleryNSPageController)?.claimKeyFocus()
            guard !isApplyingSelection else {
                flushPendingApply()
                return
            }
            let index = pageController.selectedIndex
            guard posts.indices.contains(index) else {
                flushPendingApply()
                return
            }
            let id = posts[index].globalID
            session.selectedPostID = id
            if selectedPostID.wrappedValue != id {
                selectedPostID.wrappedValue = id
            }
            flushPendingApply()
        }

        private func flushPendingApply() {
            guard let pending = pendingApply else { return }
            pendingApply = nil
            apply(
                posts: pending.posts,
                selectedPostID: pending.selectedPostID,
                pageContent: pending.pageContent,
                forceContentRefresh: pending.forceContentRefresh
            )
        }
    }
}

/// Intercepts vertical trackpad swipes before NSPageController can spring-back.
final class GalleryNSPageController: NSPageController {
    var isZoomed = false
    var onVerticalDismissScroll: ((NSEvent) -> Bool)?
    var onKeyboardDismiss: (() -> Void)?
    var onKeyboardMove: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidAppear() {
        super.viewDidAppear()
        claimKeyFocus()
    }

    func claimKeyFocus() {
        view.window?.makeFirstResponder(self)
    }

    override func scrollWheel(with event: NSEvent) {
        if !isZoomed, onVerticalDismissScroll?(event) == true {
            return
        }
        super.scrollWheel(with: event)
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53: // escape
            onKeyboardDismiss?()
        case 123: // left arrow
            onKeyboardMove?(-1)
        case 124: // right arrow
            onKeyboardMove?(1)
        default:
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        onKeyboardDismiss?()
    }
}
#endif
