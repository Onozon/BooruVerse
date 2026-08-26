#pragma once

#include "core/Models.h"

#include <QRectF>
#include <QVector>

struct GalleryLayoutResult {
    int columns = 1;
    double columnWidth = 160;
    double contentHeight = 0;
    QVector<QRectF> frames;
};

GalleryLayoutResult buildGalleryLayout(const QVector<BooruPost> &posts, double innerWidth, int preferredTileWidth,
                                       TilingMode mode, bool compact);
