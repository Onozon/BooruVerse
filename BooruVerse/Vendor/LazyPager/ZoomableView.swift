#if canImport(UIKit)
import UIKit
//
//  ZoomableView.swift
//  LazyPager
//
//  Created by Brian Floersch on 7/4/23.
//

import Foundation
import UIKit
import SwiftUI

class ZoomableView<Element, Content: View>: UIScrollView, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    
    var trailingConstraint: NSLayoutConstraint?
    var leadingConstraint: NSLayoutConstraint?
    var topConstraint: NSLayoutConstraint?
    var bottomConstraint: NSLayoutConstraint?
    var contentTopToContent: NSLayoutConstraint!
    var contentTopToFrame: NSLayoutConstraint!
    var contentBottomToFrame: NSLayoutConstraint!
    var contentBottomToView: NSLayoutConstraint!
    
    var config: Config<Element>
    var bottomView: UIView
    
    var allowScroll: Bool = true {
        didSet {
            if allowScroll, config.direction == .horizontal {
                contentTopToFrame.isActive = false
                contentBottomToFrame.isActive = false
                bottomView.isHidden = false
                
                contentTopToContent.isActive = true
                contentBottomToView.isActive = true
            } else {
                contentTopToContent.isActive = false
                contentBottomToView.isActive = false
                
                contentTopToFrame.isActive = true
                contentBottomToFrame.isActive = true
                bottomView.isHidden = true
            }
        }
    }
    
    var wasTracking = false
    var isZoomHappening = false
    var dismissEnabled = false // Contorlled by PagerView to prevent flicker
    var lastInset: CGFloat = 0
    var currentZoomInsetAnimation: UIViewPropertyAnimator?
    private var isClampingOffset = false
    
    var hostingController: UIHostingController<Content>
    var index: Int
    var data: Element
    var doubleTap: DoubleTap?
    var lastBoundsSize: CGSize?
    
    var view: UIView {
        return hostingController.view
    }
    
    init(hostingController: UIHostingController<Content>, index: Int, data: Element, config: Config<Element>) {
        self.index = index
        self.hostingController = hostingController
        self.data = data
        self.config = config
        
        let v = UIView()
        self.bottomView = v
        
        super.init(frame: .zero)
        
        translatesAutoresizingMaskIntoConstraints = false
        delegate = self
        panGestureRecognizer.delegate = self
        
        updateZoomConfig()
        
        bouncesZoom = true
        backgroundColor = .clear
        alwaysBounceVertical = false
        alwaysBounceHorizontal = false
        contentInsetAdjustmentBehavior = .never
        if config.dismissCallback != nil {
            alwaysBounceVertical = true
        }
        showsVerticalScrollIndicator = false
        showsHorizontalScrollIndicator = false
        
        view.translatesAutoresizingMaskIntoConstraints = false
        view.backgroundColor = .clear
        decelerationRate = .fast
        // DEBUG
//        backgroundColor = .red
        addSubview(view)
        
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.widthAnchor.constraint(equalTo: frameLayoutGuide.widthAnchor),
            view.heightAnchor.constraint(equalTo: frameLayoutGuide.heightAnchor),
        ])
        
        contentTopToFrame = view.topAnchor.constraint(equalTo: contentLayoutGuide.topAnchor)
        contentTopToContent = view.topAnchor.constraint(equalTo: topAnchor)
        contentBottomToFrame = view.bottomAnchor.constraint(equalTo: contentLayoutGuide.bottomAnchor)
        contentBottomToView = view.bottomAnchor.constraint(equalTo: bottomView.topAnchor)
        
        v.translatesAutoresizingMaskIntoConstraints = false
        addSubview(v)

//        This is for future support of a drawer view
        let constant: CGFloat = config.dismissCallback == nil ? 0 : 1

        NSLayoutConstraint.activate([
          v.bottomAnchor.constraint(equalTo: bottomAnchor),
          v.leadingAnchor.constraint(equalTo: frameLayoutGuide.leadingAnchor),
          v.trailingAnchor.constraint(equalTo: frameLayoutGuide.trailingAnchor),
          v.heightAnchor.constraint(equalToConstant: constant)
        ])
        
        var singleTapGesture: UITapGestureRecognizer?
        if config.tapCallback != nil {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(singleTap(_:)))
            gesture.numberOfTapsRequired = 1
            gesture.numberOfTouchesRequired = 1
            addGestureRecognizer(gesture)
            singleTapGesture = gesture
        }
                
        func setupDoubleTapGesture() {
            let doubleTapRecognizer = UITapGestureRecognizer(target: self, action: #selector(onDoubleTap(_:)))
            doubleTapRecognizer.numberOfTapsRequired = 2
            doubleTapRecognizer.numberOfTouchesRequired = 1
            addGestureRecognizer(doubleTapRecognizer)            
            singleTapGesture?.require(toFail: doubleTapRecognizer)
        }
        
        if case .scale = doubleTap {
            setupDoubleTapGesture()
        } else if config.doubleTapCallback != nil {
            setupDoubleTapGesture()
        }
        
        DispatchQueue.main.async {
            self.updateState()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("Not implemented")
    }
    
    func updateZoomConfig() {
        switch config.zoomConfigGetter(data) {
        case .disabled:
            maximumZoomScale = 1
            minimumZoomScale = 1
            doubleTap = nil
        case let .custom(min, max, doubleTap):
            minimumZoomScale = min
            maximumZoomScale = max
            self.doubleTap = doubleTap
        }
    }
    
    @objc func singleTap(_ recognizer: UITapGestureRecognizer) {
        config.tapCallback?()
    }
    
    @objc func onDoubleTap(_ recognizer: UITapGestureRecognizer) {
        config.doubleTapCallback?()
        
        if case let .scale(scale) = doubleTap {
            let pointInView = recognizer.location(in: view)
            zoom(at: pointInView, scale: scale)
            updateInsets()
        }
    }
    
    func updateState() {
        updateZoomConfig()
        let isAtMinimumZoom = zoomScale <= minimumZoomScale + 0.01
        allowScroll = isAtMinimumZoom
        // Bounce vertically only for dismiss-at-1x; when zoomed it steals vertical pan.
        alwaysBounceVertical = isAtMinimumZoom && config.dismissCallback != nil
        // Disable the outer pager while zoomed so edge pan can't change pages.
        if let pager = superview as? UIScrollView, pager !== self {
            if !isAtMinimumZoom {
                pager.isScrollEnabled = false
            } else if !pager.isScrollEnabled {
                pager.isScrollEnabled = true
            }
        }

        if contentOffset.y > config.pinchGestureEnableOffset, allowScroll {
            pinchGestureRecognizer?.isEnabled = false
        } else {
            pinchGestureRecognizer?.isEnabled = true
        }
        
        if allowScroll {
            if dismissEnabled, config.dismissCallback != nil {
                let offset = contentOffset.y
                if offset < 0 {
                    let absoluteDragOffset = normalize(from: 0, at: abs(offset), to: frame.size.height)
                    let fadeOffset = normalize(from: 0, at: absoluteDragOffset, to: config.fullFadeOnDragAt)
                    config.backgroundOpacity?.wrappedValue = 1 - fadeOffset
                } else {
                    DispatchQueue.main.async {
                        self.config.backgroundOpacity?.wrappedValue = 1
                    }
                }
            }
            wasTracking = isTracking
        }
    }
    
    func zoom(at point: CGPoint, scale: CGFloat) {
        let mid = lerp(from: minimumZoomScale, to: maximumZoomScale, by: scale)
        let newZoomScale = zoomScale == minimumZoomScale ? mid : minimumZoomScale
        let size = bounds.size
        let w = size.width / newZoomScale
        let h = size.height / newZoomScale
        let x = point.x - (w * 0.5)
        let y = point.y - (h * 0.5)
        zoom(to: CGRect(x: x, y: y, width: w, height: h), animated: true)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        // Ensures insets are updated when the screen rotates
        if bounds.size != lastBoundsSize {
            lastBoundsSize = bounds.size
            updateInsets()
        }
    }
    
    // MARK: UIScrollViewDelegate methods
    
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        isZoomHappening = true
        updateState()
    }
    
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        isZoomHappening = false
        updateState()
        updateInsets()
        clampOffsetToAspectFitImageIfNeeded()
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updateState()
        clampOffsetToAspectFitImageIfNeeded()
    }
    
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return view
    }
    
    func updateInsets() {
        // Use the zoomed view frame (not SwiftUI intrinsicContentSize — often invalid and
        // was clamping vertical pan to the vertical center / "equator").
        let scrollViewSize = bounds.size
        let zoomViewSize = view.frame.size
        guard scrollViewSize.width > 0, scrollViewSize.height > 0 else { return }

        let horizontalInset = max(0, (scrollViewSize.width - zoomViewSize.width) / 2)
        let verticalInset = max(0, (scrollViewSize.height - zoomViewSize.height) / 2)
        contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }

    /// Zoom targets the full page (including letterbox/pillarbox). Clamp pan so the
    /// viewport stays over the aspect-fit media rect instead of scrolling into bars.
    private func clampOffsetToAspectFitImageIfNeeded() {
        guard !isClampingOffset else { return }
        guard zoomScale > minimumZoomScale + 0.01 else { return }
        guard let aspect = config.contentAspectRatio?(data), aspect > 0 else { return }

        // UIScrollView keeps the zoom-view bounds unscaled; contentOffset is in
        // scaled content space (bounds * zoomScale).
        let contentBounds = view.bounds.size
        let viewport = bounds.size
        guard contentBounds.width > 1, contentBounds.height > 1 else { return }
        guard viewport.width > 1, viewport.height > 1 else { return }

        let fit = aspectFitSize(aspect: aspect, in: contentBounds)
        let imageOrigin = CGPoint(
            x: (contentBounds.width - fit.width) * 0.5,
            y: (contentBounds.height - fit.height) * 0.5
        )
        let scaledImage = CGRect(
            x: imageOrigin.x * zoomScale,
            y: imageOrigin.y * zoomScale,
            width: fit.width * zoomScale,
            height: fit.height * zoomScale
        )

        var offset = contentOffset
        if scaledImage.width <= viewport.width {
            offset.x = scaledImage.midX - viewport.width * 0.5
        } else {
            let minX = scaledImage.minX
            let maxX = scaledImage.maxX - viewport.width
            offset.x = min(max(offset.x, minX), maxX)
        }

        if scaledImage.height <= viewport.height {
            offset.y = scaledImage.midY - viewport.height * 0.5
        } else {
            let minY = scaledImage.minY
            let maxY = scaledImage.maxY - viewport.height
            offset.y = min(max(offset.y, minY), maxY)
        }

        guard abs(offset.x - contentOffset.x) > 0.05
                || abs(offset.y - contentOffset.y) > 0.05 else { return }

        isClampingOffset = true
        contentOffset = offset
        isClampingOffset = false
    }

    private func aspectFitSize(aspect: CGFloat, in bounds: CGSize) -> CGSize {
        if bounds.width / bounds.height > aspect {
            let height = bounds.height
            return CGSize(width: height * aspect, height: height)
        } else {
            let width = bounds.width
            return CGSize(width: width, height: width / aspect)
        }
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updateInsets()
        clampOffsetToAspectFitImageIfNeeded()
        config.onZoomHandler?(data, scrollView.zoomScale)
    }

    func resetZoomForReuse() {
        currentZoomInsetAnimation?.stopAnimation(true)
        currentZoomInsetAnimation = nil
        isZoomHappening = false
        setZoomScale(minimumZoomScale, animated: false)
        contentOffset = .zero
        updateState()
        updateInsets()
        config.onZoomHandler?(data, zoomScale)
    }
    
    
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        
        let percentage = contentOffset.y / (contentSize.height - bounds.size.height)
        
        if wasTracking,
           percentage < -config.dismissTriggerOffset,
           !isZoomHappening,
           velocity.y < -config.dismissVelocity,
           config.dismissCallback != nil {
            
            dismissEnabled = false // prevent touch interaction from messing with animation of opacity.
            let ogFram = frame.origin
            
            withAnimation(.linear(duration: self.config.dismissAnimationLength)) {
                self.config.backgroundOpacity?.wrappedValue = 0
            }
            
            frame.origin.y = -contentOffset.y
            
            UIView.animate(withDuration: self.config.dismissAnimationLength, animations: {
                self.frame.origin = CGPoint(x: ogFram.x, y: self.frame.size.height)
            }) { _ in
                if self.config.shouldCancelSwiftUIAnimationsOnDismiss {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        self.config.dismissCallback?()
                    }
                } else {
                    self.config.dismissCallback?()
                }
            }
        }
    }
    
    // MARK: UIGestureRecognizerDelegate
    
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // We only want to intercept our own pan gesture.
        guard gestureRecognizer == self.panGestureRecognizer else {
            return true
        }

        let panGesture = self.panGestureRecognizer
        let velocity = panGesture.velocity(in: self)

        let isZoomed = zoomScale > minimumZoomScale + 0.01
        // While zoomed, never hand off to the pager — overscroll must not change pages
        // (and returning to a page must not keep a leftover zoom from edge-handoff).
        if isZoomed {
            return true
        }

        // This logic is for the horizontal pager.
        if config.direction == .horizontal {
            // If the swipe is mostly vertical, it's for dismissal. Let it happen.
            if abs(velocity.y) > abs(velocity.x) {
                return true
            }
            // Not zoomed: pager owns horizontal paging.
            return false
        } else { // Vertical Pager
            if abs(velocity.x) > abs(velocity.y) {
                return true
            }
            return false
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // We no longer need simultaneous recognition. This simplifies the logic and
        // prevents the differential panning issues.
        return false
    }
}
#endif
