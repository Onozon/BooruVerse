#ifndef CACHEMANAGER_H
#define CACHEMANAGER_H

#include <QObject>
#include <QString>
#include <QDir>
#include <QPixmap>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QHash>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonDocument>
#include <QList>
#include <QDateTime>
#include "core/lockmanager.h"

class CacheManager : public QObject
{
    Q_OBJECT

public:
    explicit CacheManager(QObject *parent = nullptr);
    ~CacheManager();

    // Кэширование превью изображений
    QString getCachedPreviewPath(const QString& url);
    void cachePreview(const QString& url, const QPixmap& pixmap);
    bool hasCachedPreview(const QString& url) const;
    
    // Кэширование миниатюр постов
    QString getCachedThumbnailPath(const QString& postId);
    void cacheThumbnail(const QString& postId, const QPixmap& pixmap);
    bool hasCachedThumbnail(const QString& postId) const;
    
    // Кэширование метаданных
    void cachePostMetadata(const QString& postId, const QByteArray& jsonData);
    QByteArray getCachedPostMetadata(const QString& postId) const;
    
    // Сохранение/загрузка списка всех пользователей
    void saveAllArtists(const QList<QJsonObject>& artists);
    QList<QJsonObject> loadAllArtists();
    bool hasCachedArtists() const;
    QDateTime getArtistsCacheDate() const;
    
    // Сохранение/загрузка постов пользователя
    void saveArtistPosts(const QString& service, const QString& artistId, const QList<QJsonObject>& posts);
    QList<QJsonObject> loadArtistPosts(const QString& service, const QString& artistId);
    bool hasCachedArtistPosts(const QString& service, const QString& artistId) const;
    QDateTime getArtistPostsCacheDate(const QString& service, const QString& artistId) const;
    
    // Очистка кэша
    void clearCache();
    qint64 getCacheSize() const;

signals:
    void previewCached(const QString& url, const QString& filepath);
    void thumbnailCached(const QString& postId, const QString& filepath);

private:
    QString getCacheDir() const;
    QString normalizeUrl(const QString& url) const;
    QString hashUrl(const QString& url) const;
    
    QDir m_cacheDir;
    QDir m_previewDir;
    QDir m_thumbnailDir;
    QDir m_metadataDir;
    QDir m_dataDir; // Для хранения JSON данных
    
    QNetworkAccessManager* m_networkManager;
    QHash<QNetworkReply*, QString> m_downloadingPreviews;
};

#endif // CACHEMANAGER_H


