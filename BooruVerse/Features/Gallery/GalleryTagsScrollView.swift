import SwiftUI

#if canImport(UIKit)
import UIKit

struct GalleryTagsScrollView: UIViewRepresentable {
    let groups: [BooruTagGroup]
    let onAddTag: (String) -> Void
    let collapsedHeight: CGFloat
    let maxExpansion: CGFloat
    var resetToken: Int
    @Binding var panelExpansion: CGFloat

    func makeCoordinator() -> Coordinator {
        Coordinator(collapsedHeight: collapsedHeight, maxExpansion: maxExpansion)
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = false
        scrollView.bounces = true
        scrollView.backgroundColor = .clear
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .normal

        let host = UIHostingController(rootView: AnyView(EmptyView()))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = true
        scrollView.addSubview(host.view)

        context.coordinator.hostingController = host
        context.coordinator.scrollView = scrollView
        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        context.coordinator.panelExpansion = $panelExpansion

        if context.coordinator.lastResetToken != resetToken {
            context.coordinator.lastResetToken = resetToken
            context.coordinator.resetExpansion(in: scrollView)
            context.coordinator.invalidateContent()
        }

        context.coordinator.syncContent(
            groups: groups,
            onAddTag: onAddTag,
            in: scrollView
        )
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        var panelExpansion: Binding<CGFloat> = .constant(0)
        let collapsedHeight: CGFloat
        let maxExpansion: CGFloat
        weak var scrollView: UIScrollView?
        var hostingController: UIHostingController<AnyView>?
        var lastResetToken: Int = -1
        var localExpansion: CGFloat = 0
        private(set) var contentHeight: CGFloat = 0
        private var contentSignature: String = ""
        private var lastLayoutWidth: CGFloat = 0
        private var isAdjustingOffset = false

        init(collapsedHeight: CGFloat, maxExpansion: CGFloat) {
            self.collapsedHeight = collapsedHeight
            self.maxExpansion = maxExpansion
        }

        private var expansionLimit: CGFloat {
            max(0, min(contentHeight - collapsedHeight, maxExpansion))
        }

        private var isInExpansionPhase: Bool {
            expansionLimit > 0.5 && localExpansion < expansionLimit - 0.5
        }

        func invalidateContent() {
            contentSignature = ""
            contentHeight = 0
        }

        func resetExpansion(in scrollView: UIScrollView) {
            localExpansion = 0
            isAdjustingOffset = true
            scrollView.setContentOffset(.zero, animated: false)
            isAdjustingOffset = false
            publishExpansion(0, animated: false)
        }

        func publishExpansion(_ value: CGFloat, animated: Bool) {
            let clamped = min(max(0, value), expansionLimit)
            localExpansion = clamped
            let binding = panelExpansion
            DispatchQueue.main.async {
                if animated {
                    withAnimation(.interpolatingSpring(duration: 0.42, bounce: 0.12)) {
                        binding.wrappedValue = clamped
                    }
                } else if abs(binding.wrappedValue - clamped) > 0.5 {
                    binding.wrappedValue = clamped
                }
            }
        }

        func syncContent(
            groups: [BooruTagGroup],
            onAddTag: @escaping (String) -> Void,
            in scrollView: UIScrollView
        ) {
            guard let host = hostingController else { return }

            let width = scrollView.bounds.width
            guard width > 0 else {
                DispatchQueue.main.async { [weak self, weak scrollView] in
                    guard let self, let scrollView else { return }
                    self.syncContent(groups: groups, onAddTag: onAddTag, in: scrollView)
                }
                return
            }

            let signature = Self.contentSignature(for: groups, width: width)
            let needsContentRebuild = signature != contentSignature || contentHeight <= 0

            if needsContentRebuild {
                contentSignature = signature
                lastLayoutWidth = width

                host.rootView = AnyView(
                    PostTagsListContent(groups: groups, onAddTag: onAddTag)
                        .frame(width: width, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                )

                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()

                let fitting = host.sizeThatFits(in: CGSize(width: width, height: .greatestFiniteMagnitude))
                contentHeight = max(ceil(fitting.height), collapsedHeight)

                host.view.frame = CGRect(x: 0, y: 0, width: width, height: contentHeight)
                scrollView.contentSize = CGSize(width: width, height: contentHeight)

                if localExpansion > expansionLimit {
                    publishExpansion(expansionLimit, animated: false)
                }
            } else if abs(width - lastLayoutWidth) > 0.5 {
                lastLayoutWidth = width
                host.view.frame.size.width = width
                scrollView.contentSize.width = width
            }

            updateBounceBehavior(in: scrollView)
            if !scrollView.isDragging && !scrollView.isDecelerating {
                clampOffset(in: scrollView)
            }
        }

        private static func contentSignature(for groups: [BooruTagGroup], width: CGFloat) -> String {
            let tags = groups.flatMap(\.tags).map(\.name).joined(separator: "|")
            return "\(Int(width.rounded()))::\(tags)"
        }

        private func updateBounceBehavior(in scrollView: UIScrollView) {
            let viewport = scrollView.bounds.height
            guard viewport > 0 else { return }
            let maxOffset = max(0, contentHeight - viewport)
            // Keep bounce enabled while expanded so pull-down can collapse the panel,
            // and when content extends beyond the viewport for normal scrolling.
            scrollView.alwaysBounceVertical = maxOffset > 1 || localExpansion > 0.5
        }

        private func clampOffset(in scrollView: UIScrollView) {
            let viewport = scrollView.bounds.height
            guard viewport > 0 else { return }
            let maxOffset = max(0, contentHeight - viewport)
            var offset = scrollView.contentOffset.y
            offset = min(max(0, offset), maxOffset)
            guard abs(scrollView.contentOffset.y - offset) > 0.5 else { return }
            isAdjustingOffset = true
            scrollView.contentOffset.y = offset
            isAdjustingOffset = false
        }

        private func resetOffset(_ scrollView: UIScrollView) {
            guard scrollView.contentOffset.y > 0.5 else { return }
            isAdjustingOffset = true
            scrollView.contentOffset = .zero
            isAdjustingOffset = false
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !isAdjustingOffset else { return }

            let offsetY = scrollView.contentOffset.y
            let maxOffset = max(0, contentHeight - scrollView.bounds.height)

            if isInExpansionPhase {
                guard scrollView.isDragging else { return }

                if offsetY > 0 {
                    let delta = min(offsetY, expansionLimit - localExpansion)
                    guard delta > 0 else { return }
                    publishExpansion(localExpansion + delta, animated: false)
                    resetOffset(scrollView)
                } else if offsetY < 0, localExpansion > 0 {
                    let delta = min(-offsetY, localExpansion)
                    publishExpansion(localExpansion - delta, animated: false)
                    resetOffset(scrollView)
                }
                return
            }

            // Fully expanded: allow normal content scrolling when content exceeds viewport.
            if maxOffset > 1 {
                return
            }

            // All content visible — pull down collapses the panel.
            if offsetY < 0, localExpansion > 0, scrollView.isDragging {
                let delta = min(-offsetY, localExpansion)
                publishExpansion(localExpansion - delta, animated: false)
                resetOffset(scrollView)
            }
        }

        func scrollViewWillEndDragging(
            _ scrollView: UIScrollView,
            withVelocity velocity: CGPoint,
            targetContentOffset: UnsafeMutablePointer<CGPoint>
        ) {
            if isInExpansionPhase {
                var projected = scrollView.contentOffset.y
                if velocity.y > 0 {
                    projected += velocity.y * 0.35
                } else if velocity.y < 0, localExpansion > 0 {
                    projected = velocity.y * 0.35
                }

                if projected > 0 {
                    let target = min(localExpansion + projected, expansionLimit)
                    targetContentOffset.pointee.y = 0
                    if target > localExpansion + 0.5 {
                        publishExpansion(target, animated: true)
                    }
                    return
                }

                if projected < 0, localExpansion > 0 {
                    targetContentOffset.pointee.y = 0
                    publishExpansion(max(0, localExpansion + projected), animated: true)
                    return
                }

                targetContentOffset.pointee.y = 0
                return
            }

            let maxOffset = max(0, contentHeight - scrollView.bounds.height)

            if maxOffset > 1 {
                targetContentOffset.pointee.y = min(max(0, targetContentOffset.pointee.y), maxOffset)
                return
            }

            // All content visible — absorb downward fling into panel collapse.
            if localExpansion > 0, velocity.y < 0 {
                targetContentOffset.pointee.y = 0
                publishExpansion(max(0, localExpansion + velocity.y * 0.35), animated: true)
                return
            }

            targetContentOffset.pointee.y = 0
        }

        func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
            updateBounceBehavior(in: scrollView)
            if !decelerate {
                clampOffset(in: scrollView)
            }
        }

        func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
            updateBounceBehavior(in: scrollView)
            clampOffset(in: scrollView)
        }
    }
}
#else
struct GalleryTagsScrollView: View {
    let groups: [BooruTagGroup]
    let onAddTag: (String) -> Void
    let collapsedHeight: CGFloat
    let maxExpansion: CGFloat
    var resetToken: Int
    @Binding var panelExpansion: CGFloat

    var body: some View {
        ScrollView {
            PostTagsListContent(groups: groups, onAddTag: onAddTag)
        }
        .scrollIndicators(.hidden)
        .onChange(of: resetToken) { _, _ in
            panelExpansion = 0
        }
    }
}
#endif
