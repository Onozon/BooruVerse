import SwiftUI

/// Left-to-right flow layout for tag chips.
/// A chip stays on the current row only when its natural width fits the remaining space.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    struct Cache {
        var sizes: [CGSize] = []
        var positions: [CGPoint] = []
        var containerWidth: CGFloat = 0
        var totalSize: CGSize = .zero
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache()
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        if proposal.height == 0 {
            let width = proposal.width ?? 0
            return CGSize(width: max(width, 0), height: 0)
        }

        guard let width = proposal.width, width > 0, width.isFinite else {
            return .zero
        }

        guard !subviews.isEmpty else {
            return CGSize(width: width, height: 0)
        }

        let layout = computeLayout(subviews: subviews, containerWidth: width)
        cache.sizes = layout.sizes
        cache.positions = layout.positions
        cache.containerWidth = width
        cache.totalSize = layout.totalSize
        return layout.totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        guard bounds.width > 0, bounds.width.isFinite,
              bounds.height > 0, bounds.height.isFinite,
              bounds.minX.isFinite, bounds.minY.isFinite else {
            return
        }
        guard !subviews.isEmpty else { return }

        let layout: (sizes: [CGSize], positions: [CGPoint], totalSize: CGSize)
        if cache.containerWidth == bounds.width,
           cache.sizes.count == subviews.count,
           cache.positions.count == subviews.count {
            layout = (cache.sizes, cache.positions, cache.totalSize)
        } else {
            let computed = computeLayout(subviews: subviews, containerWidth: bounds.width)
            cache.sizes = computed.sizes
            cache.positions = computed.positions
            cache.containerWidth = bounds.width
            cache.totalSize = computed.totalSize
            layout = computed
        }

        for index in subviews.indices {
            let size = layout.sizes[index]
            guard size.width > 0, size.height > 0 else { continue }

            subviewPlace(
                subviews[index],
                at: CGPoint(
                    x: bounds.minX + layout.positions[index].x,
                    y: bounds.minY + layout.positions[index].y
                ),
                size: size
            )
        }
    }

    private func subviewPlace(_ subview: LayoutSubview, at point: CGPoint, size: CGSize) {
        subview.place(
            at: point,
            anchor: .topLeading,
            proposal: ProposedViewSize(width: size.width, height: size.height)
        )
    }

    private func computeLayout(subviews: Subviews, containerWidth: CGFloat) -> (sizes: [CGSize], positions: [CGPoint], totalSize: CGSize) {
        var sizes: [CGSize] = []
        sizes.reserveCapacity(subviews.count)

        for subview in subviews {
            sizes.append(chipSize(subview, containerWidth: containerWidth))
        }

        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var positions: [CGPoint] = []
        positions.reserveCapacity(subviews.count)

        for size in sizes {
            if x > 0, x + size.width > containerWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }

            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
        }

        let totalHeight = subviews.isEmpty ? 0 : y + rowHeight
        return (
            sizes: sizes,
            positions: positions,
            totalSize: CGSize(width: containerWidth, height: totalHeight)
        )
    }

    private func chipSize(_ subview: LayoutSubview, containerWidth: CGFloat) -> CGSize {
        guard containerWidth > 0 else { return .zero }

        let rowProposal = ProposedViewSize(width: containerWidth, height: nil)
        let intrinsic = subview.sizeThatFits(rowProposal)

        if intrinsic.width > 0, intrinsic.width <= containerWidth, intrinsic.height > 0 {
            return intrinsic
        }

        let wrapped = subview.sizeThatFits(ProposedViewSize(width: containerWidth, height: nil))
        return CGSize(
            width: min(max(wrapped.width, 0), containerWidth),
            height: max(wrapped.height, 0)
        )
    }
}