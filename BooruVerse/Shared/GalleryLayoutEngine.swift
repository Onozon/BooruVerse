import CoreGraphics
import Foundation

enum GalleryLayoutMetrics {
    static let spacing: CGFloat = 10
    static let gridPadding: CGFloat = 16
    static let minTileWidth: CGFloat = 160
    static let captionBlockHeight: CGFloat = 22
}

enum GalleryLayoutEngine {
    struct ColumnItem: Identifiable {
        var id: String { post.globalID }
        let post: BooruPost
        let index: Int
    }

    static func columnCount(for containerWidth: CGFloat) -> Int {
        guard containerWidth > 0 else { return 1 }
        return max(
            1,
            Int((containerWidth + GalleryLayoutMetrics.spacing) / (GalleryLayoutMetrics.minTileWidth + GalleryLayoutMetrics.spacing))
        )
    }

    static func columnWidth(for containerWidth: CGFloat, columnCount: Int) -> CGFloat {
        guard containerWidth > 0, columnCount > 0 else { return GalleryLayoutMetrics.minTileWidth }
        let totalSpacing = GalleryLayoutMetrics.spacing * CGFloat(max(columnCount - 1, 0))
        let available = max(0, containerWidth - totalSpacing)
        return floor(available / CGFloat(columnCount))
    }

    static func gridWidth(columnCount: Int, columnWidth: CGFloat) -> CGFloat {
        guard columnCount > 0 else { return 0 }
        let spacing = GalleryLayoutMetrics.spacing * CGFloat(max(columnCount - 1, 0))
        return columnWidth * CGFloat(columnCount) + spacing
    }

    static func tileHeight(for post: BooruPost, tileWidth: CGFloat) -> CGFloat {
        tileWidth / post.aspectRatio + GalleryLayoutMetrics.captionBlockHeight
    }

    static func masonryColumns(
        posts: [BooruPost],
        columnCount: Int,
        columnWidth: CGFloat
    ) -> [[ColumnItem]] {
        guard columnCount > 0 else { return [] }

        var columns = Array(
            repeating: (items: [ColumnItem](), height: CGFloat(0)),
            count: columnCount
        )

        for (index, post) in posts.enumerated() {
            let tileHeight = tileHeight(for: post, tileWidth: columnWidth)
            let columnIndex = columns.indices.min(by: { columns[$0].height < columns[$1].height }) ?? 0
            columns[columnIndex].items.append(ColumnItem(post: post, index: index))
            columns[columnIndex].height += tileHeight + GalleryLayoutMetrics.spacing
        }

        return columns.map(\.items)
    }
}
