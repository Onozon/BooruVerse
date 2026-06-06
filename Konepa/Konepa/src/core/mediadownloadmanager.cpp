#include "core/mediadownloadmanager.h"
#include <QNetworkRequest>
#include <QDir>
#include <QFileInfo>
#include <QDebug>

MediaDownloadManager* MediaDownloadManager::s_instance = nullptr;

MediaDownloadManager* MediaDownloadManager::instance()
{
    if (!s_instance) {
        s_instance = new MediaDownloadManager();
    }
    return s_instance;
}

MediaDownloadManager::MediaDownloadManager(QObject* parent)
    : QObject(parent)
{
    m_networkManager = new QNetworkAccessManager(this);
}

MediaDownloadManager::~MediaDownloadManager()
{
    // Отменяем все активные загрузки
    for (auto it = m_activeDownloads.begin(); it != m_activeDownloads.end(); ++it) {
        if (it.value().reply) {
            it.value().reply->abort();
            it.value().reply->deleteLater();
        }
    }
    m_activeDownloads.clear();
}

bool MediaDownloadManager::startDownload(const QString& url, const QString& filepath, IMediaDownloadSubscriber* subscriber)
{
    QString normalizedUrl = url;
    if (!normalizedUrl.startsWith("http://") && !normalizedUrl.startsWith("https://")) {
        if (normalizedUrl.startsWith("/")) {
            normalizedUrl = QString("https://kemono.cr%1").arg(normalizedUrl);
        } else {
            normalizedUrl = QString("https://kemono.cr/%1").arg(normalizedUrl);
        }
    }
    
    // Проверяем, не загружается ли уже этот файл
    if (m_activeDownloads.contains(normalizedUrl)) {
        MediaDownloadInfo& info = m_activeDownloads[normalizedUrl];
        
        // Если загрузка уже завершена, сразу уведомляем подписчика
        if (info.isCompleted) {
            if (subscriber) {
                subscriber->onDownloadFinished(normalizedUrl, info.filepath, !info.hasError);
            }
            return true;
        }
        
        // Если загрузка в процессе, просто подписываем
        if (subscriber) {
            subscribeToDownload(normalizedUrl, subscriber);
            // Отправляем текущий прогресс
            subscriber->onDownloadProgress(normalizedUrl, info.bytesReceived, info.bytesTotal);
        }
        return true;
    }
    
    // Проверяем, существует ли файл
    QFileInfo fileInfo(filepath);
    if (fileInfo.exists() && fileInfo.size() > 0) {
        // Файл уже существует, уведомляем подписчика
        if (subscriber) {
            subscriber->onDownloadFinished(normalizedUrl, filepath, true);
        }
        return true;
    }
    
    // Создаем директорию, если нужно
    QDir dir = fileInfo.dir();
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    
    // Создаем новую загрузку
    MediaDownloadInfo info;
    info.filepath = filepath;
    info.bytesReceived = 0;
    info.bytesTotal = 0;
    info.isCompleted = false;
    info.hasError = false;
    
    if (subscriber) {
        QObject* obj = dynamic_cast<QObject*>(subscriber);
        if (obj) {
            info.subscribers.insert(obj);
            m_subscriberUrls[obj].insert(normalizedUrl);
        }
    }
    
    // Создаем запрос
    QNetworkRequest request;
    request.setUrl(QUrl(normalizedUrl));
    request.setRawHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
    request.setRawHeader("Referer", "https://kemono.cr/");
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    
    QNetworkReply* reply = m_networkManager->get(request);
    info.reply = reply;
    
    // Подключаем сигналы
    connect(reply, &QNetworkReply::downloadProgress, this, &MediaDownloadManager::onDownloadProgress);
    connect(reply, &QNetworkReply::finished, this, &MediaDownloadManager::onDownloadFinished);
    
    // Сохраняем reply в userData для идентификации в слотах
    reply->setProperty("downloadUrl", normalizedUrl);
    
    m_activeDownloads[normalizedUrl] = info;
    
    return true;
}

void MediaDownloadManager::subscribeToDownload(const QString& url, IMediaDownloadSubscriber* subscriber)
{
    if (!subscriber) return;
    
    QString normalizedUrl = url;
    if (!normalizedUrl.startsWith("http://") && !normalizedUrl.startsWith("https://")) {
        if (normalizedUrl.startsWith("/")) {
            normalizedUrl = QString("https://kemono.cr%1").arg(normalizedUrl);
        } else {
            normalizedUrl = QString("https://kemono.cr/%1").arg(normalizedUrl);
        }
    }
    
    if (!m_activeDownloads.contains(normalizedUrl)) {
        return;
    }
    
    QObject* obj = dynamic_cast<QObject*>(subscriber);
    if (!obj) {
        return;
    }
    
    MediaDownloadInfo& info = m_activeDownloads[normalizedUrl];
    info.subscribers.insert(obj);
    m_subscriberUrls[obj].insert(normalizedUrl);
    
    // Отправляем текущий прогресс
    if (info.bytesTotal > 0) {
        subscriber->onDownloadProgress(normalizedUrl, info.bytesReceived, info.bytesTotal);
    }
    
    // Если загрузка уже завершена, уведомляем сразу
    if (info.isCompleted) {
        subscriber->onDownloadFinished(normalizedUrl, info.filepath, !info.hasError);
    }
}

void MediaDownloadManager::unsubscribeFromDownload(const QString& url, IMediaDownloadSubscriber* subscriber)
{
    if (!subscriber) return;
    
    QString normalizedUrl = url;
    if (!normalizedUrl.startsWith("http://") && !normalizedUrl.startsWith("https://")) {
        if (normalizedUrl.startsWith("/")) {
            normalizedUrl = QString("https://kemono.cr%1").arg(normalizedUrl);
        } else {
            normalizedUrl = QString("https://kemono.cr/%1").arg(normalizedUrl);
        }
    }
    
    QObject* obj = dynamic_cast<QObject*>(subscriber);
    if (!obj) {
        return;
    }
    
    if (m_activeDownloads.contains(normalizedUrl)) {
        MediaDownloadInfo& info = m_activeDownloads[normalizedUrl];
        info.subscribers.remove(obj);
    }
    
    if (m_subscriberUrls.contains(obj)) {
        m_subscriberUrls[obj].remove(normalizedUrl);
        if (m_subscriberUrls[obj].isEmpty()) {
            m_subscriberUrls.remove(obj);
        }
    }
}

bool MediaDownloadManager::isDownloading(const QString& url) const
{
    QString normalizedUrl = url;
    if (!normalizedUrl.startsWith("http://") && !normalizedUrl.startsWith("https://")) {
        if (normalizedUrl.startsWith("/")) {
            normalizedUrl = QString("https://kemono.cr%1").arg(normalizedUrl);
        } else {
            normalizedUrl = QString("https://kemono.cr/%1").arg(normalizedUrl);
        }
    }
    
    if (!m_activeDownloads.contains(normalizedUrl)) {
        return false;
    }
    
    const MediaDownloadInfo& info = m_activeDownloads[normalizedUrl];
    return !info.isCompleted && info.reply != nullptr;
}

bool MediaDownloadManager::getDownloadProgress(const QString& url, qint64& bytesReceived, qint64& bytesTotal) const
{
    QString normalizedUrl = url;
    if (!normalizedUrl.startsWith("http://") && !normalizedUrl.startsWith("https://")) {
        if (normalizedUrl.startsWith("/")) {
            normalizedUrl = QString("https://kemono.cr%1").arg(normalizedUrl);
        } else {
            normalizedUrl = QString("https://kemono.cr/%1").arg(normalizedUrl);
        }
    }
    
    if (!m_activeDownloads.contains(normalizedUrl)) {
        return false;
    }
    
    const MediaDownloadInfo& info = m_activeDownloads[normalizedUrl];
    bytesReceived = info.bytesReceived;
    bytesTotal = info.bytesTotal;
    return true;
}

bool MediaDownloadManager::isDownloadCompleted(const QString& url, QString& filepath) const
{
    QString normalizedUrl = url;
    if (!normalizedUrl.startsWith("http://") && !normalizedUrl.startsWith("https://")) {
        if (normalizedUrl.startsWith("/")) {
            normalizedUrl = QString("https://kemono.cr%1").arg(normalizedUrl);
        } else {
            normalizedUrl = QString("https://kemono.cr/%1").arg(normalizedUrl);
        }
    }
    
    if (!m_activeDownloads.contains(normalizedUrl)) {
        return false;
    }
    
    const MediaDownloadInfo& info = m_activeDownloads[normalizedUrl];
    if (info.isCompleted && !info.hasError) {
        filepath = info.filepath;
        return true;
    }
    
    return false;
}

void MediaDownloadManager::cancelDownload(const QString& url)
{
    QString normalizedUrl = url;
    if (!normalizedUrl.startsWith("http://") && !normalizedUrl.startsWith("https://")) {
        if (normalizedUrl.startsWith("/")) {
            normalizedUrl = QString("https://kemono.cr%1").arg(normalizedUrl);
        } else {
            normalizedUrl = QString("https://kemono.cr/%1").arg(normalizedUrl);
        }
    }
    
    if (m_activeDownloads.contains(normalizedUrl)) {
        MediaDownloadInfo& info = m_activeDownloads[normalizedUrl];
        if (info.reply) {
            info.reply->abort();
            info.reply->deleteLater();
        }
        m_activeDownloads.remove(normalizedUrl);
    }
}

void MediaDownloadManager::onDownloadProgress(qint64 bytesReceived, qint64 bytesTotal)
{
    QNetworkReply* reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    
    QString url = reply->property("downloadUrl").toString();
    if (url.isEmpty() || !m_activeDownloads.contains(url)) {
        return;
    }
    
    MediaDownloadInfo& info = m_activeDownloads[url];
    info.bytesReceived = bytesReceived;
    info.bytesTotal = bytesTotal;
    
    // Уведомляем всех подписчиков
    QSet<QObject*> toRemove;
    for (QObject* subscriber : info.subscribers) {
        IMediaDownloadSubscriber* sub = dynamic_cast<IMediaDownloadSubscriber*>(subscriber);
        if (sub) {
            sub->onDownloadProgress(url, bytesReceived, bytesTotal);
        } else {
            // Подписчик был удален или не реализует интерфейс
            toRemove.insert(subscriber);
        }
    }
    
    // Удаляем недействительные подписки
    for (QObject* subscriber : toRemove) {
        info.subscribers.remove(subscriber);
        if (m_subscriberUrls.contains(subscriber)) {
            m_subscriberUrls[subscriber].remove(url);
            if (m_subscriberUrls[subscriber].isEmpty()) {
                m_subscriberUrls.remove(subscriber);
            }
        }
    }
}

void MediaDownloadManager::onDownloadFinished()
{
    QNetworkReply* reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) return;
    
    QString url = reply->property("downloadUrl").toString();
    if (url.isEmpty() || !m_activeDownloads.contains(url)) {
        reply->deleteLater();
        return;
    }
    
    MediaDownloadInfo& info = m_activeDownloads[url];
    bool success = false;
    
    if (reply->error() == QNetworkReply::NoError) {
        QByteArray data = reply->readAll();
        QFile file(info.filepath);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(data);
            file.close();
            success = true;
        } else {
            info.hasError = true;
            info.errorString = "Ошибка сохранения файла";
        }
    } else {
        info.hasError = true;
        info.errorString = reply->errorString();
    }
    
    info.isCompleted = true;
    
    // Уведомляем всех подписчиков
    QSet<QObject*> toRemove;
    for (QObject* subscriber : info.subscribers) {
        IMediaDownloadSubscriber* sub = dynamic_cast<IMediaDownloadSubscriber*>(subscriber);
        if (sub) {
            sub->onDownloadFinished(url, info.filepath, success);
        } else {
            toRemove.insert(subscriber);
        }
    }
    
    // Удаляем недействительные подписки
    for (QObject* subscriber : toRemove) {
        info.subscribers.remove(subscriber);
        if (m_subscriberUrls.contains(subscriber)) {
            m_subscriberUrls[subscriber].remove(url);
            if (m_subscriberUrls[subscriber].isEmpty()) {
                m_subscriberUrls.remove(subscriber);
            }
        }
    }
    
    // Очищаем загрузку через некоторое время (чтобы другие окна могли подписаться)
    // Но не удаляем сразу, чтобы можно было подписаться на завершенную загрузку
    reply->deleteLater();
}

