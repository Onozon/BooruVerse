#ifndef MEDIADOWNLOADMANAGER_H
#define MEDIADOWNLOADMANAGER_H

#include <QObject>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QMap>
#include <QSet>
#include <QString>
#include <QFile>
#include <QPointer>

// Структура для отслеживания загрузки
struct MediaDownloadInfo {
    QNetworkReply* reply;
    QString filepath;
    QSet<QObject*> subscribers; // QObject* объектов, реализующих IMediaDownloadSubscriber
    qint64 bytesReceived;
    qint64 bytesTotal;
    bool isCompleted;
    bool hasError;
    QString errorString;
};

// Интерфейс для подписчиков на прогресс загрузки
class IMediaDownloadSubscriber {
public:
    virtual ~IMediaDownloadSubscriber() = default;
    virtual void onDownloadProgress(const QString& url, qint64 bytesReceived, qint64 bytesTotal) = 0;
    virtual void onDownloadFinished(const QString& url, const QString& filepath, bool success) = 0;
};

class MediaDownloadManager : public QObject
{
    Q_OBJECT

public:
    static MediaDownloadManager* instance();
    
    // Начать загрузку (или вернуть существующую)
    bool startDownload(const QString& url, const QString& filepath, IMediaDownloadSubscriber* subscriber);
    
    // Подписаться на существующую загрузку
    void subscribeToDownload(const QString& url, IMediaDownloadSubscriber* subscriber);
    
    // Отписаться от загрузки
    void unsubscribeFromDownload(const QString& url, IMediaDownloadSubscriber* subscriber);
    
    // Проверить, загружается ли файл
    bool isDownloading(const QString& url) const;
    
    // Получить текущий прогресс загрузки
    bool getDownloadProgress(const QString& url, qint64& bytesReceived, qint64& bytesTotal) const;
    
    // Проверить, завершена ли загрузка
    bool isDownloadCompleted(const QString& url, QString& filepath) const;
    
    // Отменить загрузку
    void cancelDownload(const QString& url);

private:
    explicit MediaDownloadManager(QObject* parent = nullptr);
    ~MediaDownloadManager();
    
    void cleanupSubscriber(QObject* subscriber);
    
private slots:
    void onDownloadProgress(qint64 bytesReceived, qint64 bytesTotal);
    void onDownloadFinished();

private:
    static MediaDownloadManager* s_instance;
    QNetworkAccessManager* m_networkManager;
    QMap<QString, MediaDownloadInfo> m_activeDownloads; // url -> download info
    QMap<QObject*, QSet<QString>> m_subscriberUrls; // subscriber -> set of urls
};

#endif // MEDIADOWNLOADMANAGER_H

