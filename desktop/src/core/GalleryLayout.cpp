#include "core/GalleryLayout.h"

#include <algorithm>
#include <cmath>

namespace {
constexpr double kSpacing = 10;
constexpr double kCaption = 22;
constexpr double kMinTile = 72;

int columnCount(double innerWidth, int preferredTileWidth, int maxColumns) {
    if (innerWidth <= 0)
        return 1;
    const double tile = std::max(double(preferredTileWidth), 1.0);
    const int raw = int((innerWidth + kSpacing) / (tile + kSpacing));
    return std::clamp(raw, 1, std::max(1, maxColumns));
}

double columnWidth(double innerWidth, int columns) {
    if (innerWidth <= 0 || columns <= 0)
        return kMinTile;
    const double spacing = kSpacing * std::max(columns - 1, 0);
    return std::floor(std::max(0.0, innerWidth - spacing) / columns);
}

double tileHeight(const BooruPost &post, double width) {
    const double aspect = std::max(post.aspectRatio(), 0.2);
    return width / aspect + kCaption;
}
}

GalleryLayoutResult buildGalleryLayout(const QVector<BooruPost> &posts, double innerWidth, int preferredTileWidth,
                                       TilingMode mode, bool compact) {
    GalleryLayoutResult result;
    const int maxCols = compact ? 3 : 10;
    result.columns = columnCount(innerWidth, preferredTileWidth, maxCols);
    result.columnWidth = columnWidth(innerWidth, result.columns);
    result.frames.resize(posts.size());

    if (posts.isEmpty() || result.columns <= 0) {
        result.contentHeight = 0;
        return result;
    }

    if (mode == TilingMode::Columns) {
        QVector<double> heights(result.columns, 0.0);
        for (int i = 0; i < posts.size(); ++i) {
            const double h = tileHeight(posts[i], result.columnWidth);
            int col = 0;
            for (int c = 1; c < result.columns; ++c) {
                if (heights[c] < heights[col])
                    col = c;
            }
            result.frames[i] = QRectF(col * (result.columnWidth + kSpacing), heights[col], result.columnWidth, h);
            heights[col] += h + kSpacing;
        }
        result.contentHeight = *std::max_element(heights.begin(), heights.end());
        return result;
    }

    double y = 0;
    int i = 0;
    while (i < posts.size()) {
        const int rowCount = std::min(result.columns, int(posts.size() - i));
        double rowH = 0;
        for (int c = 0; c < rowCount; ++c)
            rowH = std::max(rowH, tileHeight(posts[i + c], result.columnWidth));
        for (int c = 0; c < rowCount; ++c) {
            const double h = tileHeight(posts[i + c], result.columnWidth);
            result.frames[i + c] = QRectF(c * (result.columnWidth + kSpacing), y, result.columnWidth, h);
        }
        y += rowH + kSpacing;
        i += rowCount;
    }
    result.contentHeight = y;
    return result;
}
