#pragma once

#include <QHash>
#include <QObject>
#include <QPixmap>
#include <QSet>
#include <QUrl>

class ThumbnailCache : public QObject {
    Q_OBJECT
public:
    explicit ThumbnailCache(QObject *parent = nullptr);

    QPixmap cached(const QUrl &url) const;
    void request(const QUrl &url);

signals:
    void ready(const QUrl &url, const QPixmap &pixmap);

private:
    QHash<QUrl, QPixmap> m_memory;
    QSet<QUrl> m_inflight;
};
