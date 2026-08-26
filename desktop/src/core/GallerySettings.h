#pragma once

#include "core/Models.h"

#include <QObject>

class GallerySettings : public QObject {
    Q_OBJECT
public:
    static GallerySettings &instance();

    int tileExtent(GallerySection section) const;
    void setTileExtent(GallerySection section, int extent);
    TilingMode tilingMode() const { return m_mode; }
    void setTilingMode(TilingMode mode);
    int preferredTileWidth(GallerySection section) const;

    RatingFilter ratingFilter() const { return m_rating; }
    void setRatingFilter(RatingFilter filter);
    bool loadFullQuality() const { return m_fullQuality; }
    void setLoadFullQuality(bool enabled);
    bool showsSidebar() const { return m_sidebar; }
    void setShowsSidebar(bool visible);
    QString downloadFolder() const { return m_downloadFolder; }
    void setDownloadFolder(const QString &path);
    bool askDownloadFolder() const { return m_askDownloadFolder; }
    void setAskDownloadFolder(bool ask);
    static QString defaultDownloadFolder();

    static int snap(int extent);
    static QString keyFor(GallerySection section);

signals:
    void changed();

private:
    explicit GallerySettings(QObject *parent = nullptr);
    void load();
    void save() const;

    int m_extents[4] = {160, 160, 160, 160};
    TilingMode m_mode = TilingMode::Columns;
    RatingFilter m_rating = RatingFilter::All;
    bool m_fullQuality = false;
    bool m_sidebar = true;
    QString m_downloadFolder;
    bool m_askDownloadFolder = false;
};
