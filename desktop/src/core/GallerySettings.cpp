#include "core/GallerySettings.h"

#include <QDir>
#include <QSettings>
#include <QStandardPaths>

GallerySettings &GallerySettings::instance() {
    static GallerySettings settings;
    return settings;
}

GallerySettings::GallerySettings(QObject *parent)
    : QObject(parent) {
    load();
}

QString GallerySettings::keyFor(GallerySection section) {
    switch (section) {
    case GallerySection::Browse:
        return QStringLiteral("browse");
    case GallerySection::Feed:
        return QStringLiteral("feed");
    case GallerySection::Favorites:
        return QStringLiteral("favorites");
    case GallerySection::Pools:
        return QStringLiteral("pools");
    }
    return QStringLiteral("browse");
}

QString GallerySettings::defaultDownloadFolder() {
    return QDir(QStandardPaths::writableLocation(QStandardPaths::DownloadLocation)).filePath(QStringLiteral("BooruVerse"));
}

int GallerySettings::snap(int extent) {
    return qBound(72, ((extent + 14) / 28) * 28, 360);
}

int GallerySettings::tileExtent(GallerySection section) const {
    return m_extents[int(section)];
}

void GallerySettings::setTileExtent(GallerySection section, int extent) {
    const int snapped = snap(extent);
    if (m_extents[int(section)] == snapped)
        return;
    m_extents[int(section)] = snapped;
    save();
    emit changed();
}

void GallerySettings::setTilingMode(TilingMode mode) {
    if (m_mode == mode)
        return;
    m_mode = mode;
    save();
    emit changed();
}

void GallerySettings::setRatingFilter(RatingFilter filter) {
    if (m_rating == filter)
        return;
    m_rating = filter;
    save();
    emit changed();
}

void GallerySettings::setLoadFullQuality(bool enabled) {
    if (m_fullQuality == enabled)
        return;
    m_fullQuality = enabled;
    save();
    emit changed();
}

void GallerySettings::setShowsSidebar(bool visible) {
    if (m_sidebar == visible)
        return;
    m_sidebar = visible;
    save();
    emit changed();
}

void GallerySettings::setDownloadFolder(const QString &path) {
    const QString cleaned = path.trimmed();
    if (cleaned.isEmpty() || m_downloadFolder == cleaned)
        return;
    m_downloadFolder = cleaned;
    save();
    emit changed();
}

void GallerySettings::setAskDownloadFolder(bool ask) {
    if (m_askDownloadFolder == ask)
        return;
    m_askDownloadFolder = ask;
    save();
    emit changed();
}

int GallerySettings::preferredTileWidth(GallerySection section) const {
    return qMax(tileExtent(section), 72);
}

void GallerySettings::load() {
    QSettings settings;
    for (int i = 0; i < 4; ++i) {
        const auto section = GallerySection(i);
        m_extents[i] = snap(settings.value(QStringLiteral("gallery/tileExtent/%1").arg(keyFor(section)), 160).toInt());
    }
    m_mode = TilingMode(settings.value(QStringLiteral("gallery/tilingMode"), int(TilingMode::Columns)).toInt());
    m_rating = RatingFilter(settings.value(QStringLiteral("app/ratingFilter"), int(RatingFilter::All)).toInt());
    m_fullQuality = settings.value(QStringLiteral("app/loadFullQuality"), false).toBool();
    m_sidebar = settings.value(QStringLiteral("app/showsSidebar"), true).toBool();
    m_downloadFolder = settings.value(QStringLiteral("downloads/folder"), defaultDownloadFolder()).toString();
    if (m_downloadFolder.isEmpty())
        m_downloadFolder = defaultDownloadFolder();
    m_askDownloadFolder = settings.value(QStringLiteral("downloads/askEveryTime"), false).toBool();
}

void GallerySettings::save() const {
    QSettings settings;
    for (int i = 0; i < 4; ++i) {
        const auto section = GallerySection(i);
        settings.setValue(QStringLiteral("gallery/tileExtent/%1").arg(keyFor(section)), m_extents[i]);
    }
    settings.setValue(QStringLiteral("gallery/tilingMode"), int(m_mode));
    settings.setValue(QStringLiteral("app/ratingFilter"), int(m_rating));
    settings.setValue(QStringLiteral("app/loadFullQuality"), m_fullQuality);
    settings.setValue(QStringLiteral("app/showsSidebar"), m_sidebar);
    settings.setValue(QStringLiteral("downloads/folder"), m_downloadFolder);
    settings.setValue(QStringLiteral("downloads/askEveryTime"), m_askDownloadFolder);
}
