import CoreGraphics
import Foundation

/// Per-tab gallery density (Browse / Feed / Favorites / pool detail).
enum GalleryScaleSection: String, CaseIterable, Sendable {
    case browse
    case feed
    case favorites
    case pools

    var defaultsKey: String {
        "BooruVerse.gallery.tileExtent.\(rawValue)"
    }
}

/// Maps a stored tile extent (pt) into column layout + pinch snap.
enum GalleryThumbScale {
    static let defaultExtent: CGFloat = GalleryLayoutMetrics.minTileWidth
    static let snapStep: CGFloat = 28

    static func maxColumns(isCompact: Bool) -> Int {
        isCompact ? 3 : 10
    }

    /// Smallest tile width that still fits `maxColumns` in `contentWidth`.
    static func minimumExtent(contentWidth: CGFloat, maxColumns: Int) -> CGFloat {
        guard contentWidth > 0, maxColumns > 0 else { return defaultExtent }
        let spacing = GalleryLayoutMetrics.spacing * CGFloat(max(maxColumns - 1, 0))
        return max(72, floor((contentWidth - spacing) / CGFloat(maxColumns)))
    }

    static func maximumExtent(contentWidth: CGFloat) -> CGFloat {
        max(contentWidth, defaultExtent)
    }

    static func clamp(
        _ extent: CGFloat,
        contentWidth: CGFloat,
        isCompact: Bool
    ) -> CGFloat {
        let maxColumns = maxColumns(isCompact: isCompact)
        let lo = minimumExtent(contentWidth: contentWidth, maxColumns: maxColumns)
        let hi = maximumExtent(contentWidth: contentWidth)
        return min(max(extent, lo), hi)
    }

    static func snap(
        _ extent: CGFloat,
        contentWidth: CGFloat,
        isCompact: Bool
    ) -> CGFloat {
        let clamped = clamp(extent, contentWidth: contentWidth, isCompact: isCompact)
        let lo = minimumExtent(contentWidth: contentWidth, maxColumns: maxColumns(isCompact: isCompact))
        let hi = maximumExtent(contentWidth: contentWidth)
        // Prefer extents that land on whole column counts at the current width.
        var candidates: [CGFloat] = [lo, hi, defaultExtent]
        let maxCols = maxColumns(isCompact: isCompact)
        for columns in 1...maxCols {
            let spacing = GalleryLayoutMetrics.spacing * CGFloat(max(columns - 1, 0))
            let width = floor((contentWidth - spacing) / CGFloat(columns))
            if width >= lo, width <= hi {
                candidates.append(width)
            }
        }
        var stepped = lo
        while stepped < hi {
            candidates.append(stepped)
            stepped += snapStep
        }
        candidates.append(hi)

        return candidates.min(by: { abs($0 - clamped) < abs($1 - clamped) }) ?? clamped
    }

    /// Columns mode: extent is preferred max tile width.
    /// Adaptive mode: extent is preferred max tile height → derive a width from a 1:1 reference.
    static func preferredTileWidth(
        extent: CGFloat,
        tilingMode: GalleryTilingMode
    ) -> CGFloat {
        switch tilingMode {
        case .columns:
            return extent
        case .adaptive:
            return max(extent - GalleryLayoutMetrics.captionBlockHeight, 72)
        }
    }
}
