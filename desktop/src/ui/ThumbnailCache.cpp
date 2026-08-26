#include "ui/ThumbnailCache.h"

#include "core/HttpClient.h"

#include <QImage>

ThumbnailCache::ThumbnailCache(QObject *parent)
    : QObject(parent) {
}

QPixmap ThumbnailCache::cached(const QUrl &url) const {
    return m_memory.value(url);
}

void ThumbnailCache::request(const QUrl &url) {
    if (url.isEmpty() || m_memory.contains(url) || m_inflight.contains(url))
        return;
    m_inflight.insert(url);
    HttpClient::instance().get(url, {}, [this, url](QByteArray data, QString error) {
        m_inflight.remove(url);
        if (!error.isEmpty() || data.isEmpty())
            return;
        QPixmap pixmap;
        if (!pixmap.loadFromData(data))
            return;
        m_memory.insert(url, pixmap);
        emit ready(url, pixmap);
    });
}
