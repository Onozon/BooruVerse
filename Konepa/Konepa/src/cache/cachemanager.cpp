#include "cache/cachemanager.h"
#include <QCryptographicHash>
#include <QFileInfo>
#include <QFile>
#include <QDebug>
#include <QStandardPaths>
#include <QDirIterator>
#include <QJsonDocument>
#include <QJsonArray>
#include <QDateTime>
#include "core/lockmanager.h"

CacheManager::CacheManager(QObject *parent)
    : QObject(parent)
{
    QString cacheBase = getCacheDir();
    m_cacheDir = QDir(cacheBase);
    m_cacheDir.mkpath(".");
    
    m_previewDir = QDir(cacheBase + "/media_previews");
    m_previewDir.mkpath(".");
    
    m_thumbnailDir = QDir(cacheBase + "/post_thumbnails");
    m_thumbnailDir.mkpath(".");
    
    m_metadataDir = QDir(cacheBase + "/posts_metadata");
    m_metadataDir.mkpath(".");
    
    m_dataDir = QDir(cacheBase + "/data");
    m_dataDir.mkpath(".");
    
    m_networkManager = new QNetworkAccessManager(this);
}

CacheManager::~CacheManager()
{
}

QString CacheManager::getCacheDir() const
{
    return QDir::currentPath() + "/cache";
}

QString CacheManager::normalizeUrl(const QString& url) const
{
    QString normalized = url;
    
    // Remove domain prefixes to get consistent path
    if (normalized.startsWith("https://kemono.cr/")) {
        normalized = normalized.mid(QString("https://kemono.cr").length());
    } else if (normalized.startsWith("https://img.kemono.cr/")) {
        normalized = normalized.mid(QString("https://img.kemono.cr").length());
    } else if (normalized.startsWith("http://kemono.cr/")) {
        normalized = normalized.mid(QString("http://kemono.cr").length());
    } else if (normalized.startsWith("https://kemono.su/")) {
        normalized = normalized.mid(QString("https://kemono.su").length());
    } else if (normalized.startsWith("https://img.kemono.su/")) {
        normalized = normalized.mid(QString("https://img.kemono.su").length());
    }
    
    // Ensure starts with /
    if (!normalized.startsWith("/")) {
        normalized = "/" + normalized;
    }
    
    return normalized;
}

QString CacheManager::hashUrl(const QString& url) const
{
    // Normalize URL before hashing to ensure consistent cache keys
    QString normalized = normalizeUrl(url);
    QCryptographicHash hash(QCryptographicHash::Md5);
    hash.addData(normalized.toUtf8());
    return hash.result().toHex();
}

QString CacheManager::getCachedPreviewPath(const QString& url)
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    QString hash = hashUrl(url);
    QString filepath = m_previewDir.absoluteFilePath(hash + ".png");
    if (QFileInfo::exists(filepath)) {
        return filepath;
    }
    return QString();
}

bool CacheManager::hasCachedPreview(const QString& url) const
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    QString hash = hashUrl(url);
    QString filepath = m_previewDir.absoluteFilePath(hash + ".png");
    return QFileInfo::exists(filepath);
}

void CacheManager::cachePreview(const QString& url, const QPixmap& pixmap)
{
    // File operations are thread-safe in Qt, no locks needed
    QString hash = hashUrl(url);
    QString filepath = m_previewDir.absoluteFilePath(hash + ".png");
    if (pixmap.save(filepath, "PNG")) {
        emit previewCached(url, filepath);
    }
}

QString CacheManager::getCachedThumbnailPath(const QString& postId)
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    QString filepath = m_thumbnailDir.absoluteFilePath(postId + ".png");
    if (QFileInfo::exists(filepath)) {
        return filepath;
    }
    return QString();
}

bool CacheManager::hasCachedThumbnail(const QString& postId) const
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    QString filepath = m_thumbnailDir.absoluteFilePath(postId + ".png");
    return QFileInfo::exists(filepath);
}

void CacheManager::cacheThumbnail(const QString& postId, const QPixmap& pixmap)
{
    // File operations are thread-safe in Qt, no locks needed
    QString filepath = m_thumbnailDir.absoluteFilePath(postId + ".png");
    if (pixmap.save(filepath, "PNG")) {
        emit thumbnailCached(postId, filepath);
    }
}

void CacheManager::cachePostMetadata(const QString& postId, const QByteArray& jsonData)
{
    // File operations are thread-safe in Qt, no locks needed
    QString filepath = m_metadataDir.absoluteFilePath(postId + "_posts.json");
    QFile file(filepath);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(jsonData);
        file.close();
    }
}

QByteArray CacheManager::getCachedPostMetadata(const QString& postId) const
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    QString filepath = m_metadataDir.absoluteFilePath(postId + "_posts.json");
    QFile file(filepath);
    if (file.open(QIODevice::ReadOnly)) {
        QByteArray data = file.readAll();
        file.close();
        return data;
    }
    return QByteArray();
}

void CacheManager::clearCache()
{
    // File operations are thread-safe in Qt, no locks needed
    // Удаляем все файлы из кэша
    QDirIterator it(m_cacheDir.absolutePath(), QDirIterator::Subdirectories);
    while (it.hasNext()) {
        QFile::remove(it.next());
    }
}

qint64 CacheManager::getCacheSize() const
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    qint64 totalSize = 0;
    QDirIterator it(m_cacheDir.absolutePath(), QDirIterator::Subdirectories);
    while (it.hasNext()) {
        QFileInfo fileInfo(it.next());
        if (fileInfo.isFile()) {
            totalSize += fileInfo.size();
        }
    }
    return totalSize;
}

void CacheManager::saveAllArtists(const QList<QJsonObject>& artists)
{
    // File operations are thread-safe in Qt, no locks needed
    QJsonArray artistsArray;
    for (const QJsonObject& artist : artists) {
        artistsArray.append(artist);
    }
    
    QJsonObject root;
    root["artists"] = artistsArray;
    root["last_updated"] = QDateTime::currentDateTime().toString(Qt::ISODate);
    root["count"] = artists.size();
    
    QJsonDocument doc(root);
    QString filepath = m_dataDir.absoluteFilePath("artists.json");
    QFile file(filepath);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(doc.toJson());
        file.close();
        qDebug() << "Saved" << artists.size() << "artists to cache";
    }
}

QList<QJsonObject> CacheManager::loadAllArtists()
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    QString filepath = m_dataDir.absoluteFilePath("artists.json");
    QFile file(filepath);
    if (!file.exists() || !file.open(QIODevice::ReadOnly)) {
        return QList<QJsonObject>();
    }
    
    QByteArray data = file.readAll();
    file.close();
    
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) {
        return QList<QJsonObject>();
    }
    
    QJsonObject root = doc.object();
    if (!root.contains("artists") || !root["artists"].isArray()) {
        return QList<QJsonObject>();
    }
    
    QJsonArray artistsArray = root["artists"].toArray();
    QList<QJsonObject> artists;
    for (const QJsonValue& value : artistsArray) {
        if (value.isObject()) {
            artists.append(value.toObject());
        }
    }
    
    qDebug() << "Loaded" << artists.size() << "artists from cache";
    return artists;
}

bool CacheManager::hasCachedArtists() const
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    QString filepath = m_dataDir.absoluteFilePath("artists.json");
    return QFile::exists(filepath);
}

QDateTime CacheManager::getArtistsCacheDate() const
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    QString filepath = m_dataDir.absoluteFilePath("artists.json");
    QFileInfo fileInfo(filepath);
    if (fileInfo.exists()) {
        return fileInfo.lastModified();
    }
    return QDateTime();
}

void CacheManager::saveArtistPosts(const QString& service, const QString& artistId, const QList<QJsonObject>& posts)
{
    // File operations are thread-safe in Qt, no locks needed
    QJsonArray postsArray;
    for (const QJsonObject& post : posts) {
        postsArray.append(post);
    }
    
    QJsonObject root;
    root["service"] = service;
    root["artist_id"] = artistId;
    root["posts"] = postsArray;
    root["last_updated"] = QDateTime::currentDateTime().toString(Qt::ISODate);
    root["count"] = posts.size();
    
    QJsonDocument doc(root);
    QString filename = QString("%1_%2_posts.json").arg(service, artistId);
    QString filepath = m_dataDir.absoluteFilePath(filename);
    QFile file(filepath);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(doc.toJson());
        file.close();
        qDebug() << "Saved" << posts.size() << "posts for artist" << artistId << "to cache";
    }
}

QList<QJsonObject> CacheManager::loadArtistPosts(const QString& service, const QString& artistId)
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    QString filename = QString("%1_%2_posts.json").arg(service, artistId);
    QString filepath = m_dataDir.absoluteFilePath(filename);
    QFile file(filepath);
    if (!file.exists() || !file.open(QIODevice::ReadOnly)) {
        return QList<QJsonObject>();
    }
    
    QByteArray data = file.readAll();
    file.close();
    
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isObject()) {
        return QList<QJsonObject>();
    }
    
    QJsonObject root = doc.object();
    if (!root.contains("posts") || !root["posts"].isArray()) {
        return QList<QJsonObject>();
    }
    
    QJsonArray postsArray = root["posts"].toArray();
    QList<QJsonObject> posts;
    for (const QJsonValue& value : postsArray) {
        if (value.isObject()) {
            posts.append(value.toObject());
        }
    }
    
    qDebug() << "Loaded" << posts.size() << "posts for artist" << artistId << "from cache";
    return posts;
}

bool CacheManager::hasCachedArtistPosts(const QString& service, const QString& artistId) const
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    QString filename = QString("%1_%2_posts.json").arg(service, artistId);
    QString filepath = m_dataDir.absoluteFilePath(filename);
    return QFile::exists(filepath);
}

QDateTime CacheManager::getArtistPostsCacheDate(const QString& service, const QString& artistId) const
{
    // File operations are thread-safe in Qt, no locks needed for read-only operations
    QString filename = QString("%1_%2_posts.json").arg(service, artistId);
    QString filepath = m_dataDir.absoluteFilePath(filename);
    QFileInfo fileInfo(filepath);
    if (fileInfo.exists()) {
        return fileInfo.lastModified();
    }
    return QDateTime();
}

