#include "app/ThumbImageProvider.h"

#include "core/HttpClient.h"

#include <QBuffer>
#include <QCache>
#include <QHash>
#include <QImage>
#include <QImageReader>
#include <QMutex>
#include <QMutexLocker>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QQuickTextureFactory>
#include <QQueue>
#include <QTimer>
#include <QUrl>

namespace {

constexpr int kDefaultMaxPx = 480;
constexpr int kHardMaxPx = 1600;
constexpr int kCacheCostLimit = 64 * 1024 * 1024;
constexpr int kMaxInFlight = 6;

QString jobKey(const QUrl &url, int maxPx) {
    return QString::number(maxPx) + QLatin1Char('|') + url.toString();
}

int clampMaxPx(int maxPx) {
    if (maxPx <= 0)
        return kDefaultMaxPx;
    return qBound(1, maxPx, kHardMaxPx);
}

QImage decodeScaled(const QByteArray &data, int maxPx) {
    maxPx = clampMaxPx(maxPx);
    QBuffer buffer;
    buffer.setData(data);
    if (!buffer.open(QIODevice::ReadOnly))
        return {};

    QImageReader reader(&buffer);
    reader.setAutoTransform(true);
    QSize size = reader.size();
    if (size.isValid()) {
        const int longest = qMax(size.width(), size.height());
        if (longest > maxPx) {
            size.scale(maxPx, maxPx, Qt::KeepAspectRatio);
            reader.setScaledSize(size);
        }
        return reader.read();
    }

    // Unknown dimensions: decode then downscale so a huge payload cannot blow RAM.
    QImage image = reader.read();
    if (image.isNull())
        return {};
    const int longest = qMax(image.width(), image.height());
    if (longest > maxPx)
        image = image.scaled(maxPx, maxPx, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    return image;
}

int imageCost(const QImage &image) {
    const qsizetype bytes = image.sizeInBytes();
    return int(qBound(qsizetype(1), bytes, qsizetype(INT_MAX)));
}

class ThumbEngine;

class ThumbWaiter final : public QQuickImageResponse {
public:
    ~ThumbWaiter() override;

    void cancel() override;
    QQuickTextureFactory *textureFactory() const override {
        return m_image.isNull() ? nullptr : QQuickTextureFactory::textureFactoryForImage(m_image);
    }
    QString errorString() const override { return m_error; }

    void complete(const QImage &image, const QString &error) {
        if (m_done)
            return;
        m_done = true;
        m_image = image;
        m_error = error;
        Q_EMIT finished();
    }

    QString key;
    bool cancelled = false;

private:
    QImage m_image;
    QString m_error;
    bool m_done = false;
};

class ThumbEngine final : public QObject {
public:
    static ThumbEngine &instance() {
        static ThumbEngine engine;
        return engine;
    }

    QQuickImageResponse *request(const QUrl &url, int maxPx) {
        maxPx = clampMaxPx(maxPx);
        auto *waiter = new ThumbWaiter;
        waiter->key = jobKey(url, maxPx);

        if (url.isEmpty()) {
            QTimer::singleShot(0, waiter, [waiter]() { waiter->complete({}, QStringLiteral("empty")); });
            return waiter;
        }

        {
            QMutexLocker lock(&m_mutex);
            if (const QImage *cached = m_cache.object(waiter->key)) {
                const QImage copy = *cached;
                lock.unlock();
                QTimer::singleShot(0, waiter, [waiter, copy]() { waiter->complete(copy, {}); });
                return waiter;
            }
        }

        Job *job = nullptr;
        {
            QMutexLocker lock(&m_mutex);
            job = m_jobs.value(waiter->key);
            if (!job) {
                job = new Job;
                job->url = url;
                job->maxPx = maxPx;
                job->key = waiter->key;
                m_jobs.insert(waiter->key, job);
                m_queued.enqueue(job);
            }
            job->waiters.append(waiter);
        }
        pump();
        return waiter;
    }

    void detach(ThumbWaiter *waiter) {
        if (!waiter || waiter->key.isEmpty())
            return;
        Job *job = nullptr;
        {
            QMutexLocker lock(&m_mutex);
            job = m_jobs.value(waiter->key);
            if (!job)
                return;
            job->waiters.removeAll(waiter);
            if (!job->waiters.isEmpty())
                return;
            if (job->reply) {
                job->reply->abort();
                return;
            }
            // Still queued: drop it so it never starts.
            m_queued.removeAll(job);
            m_jobs.remove(job->key);
            delete job;
        }
    }

    void purge() {
        QMutexLocker lock(&m_mutex);
        m_cache.clear();
    }

private:
    struct Job {
        QUrl url;
        QNetworkReply *reply = nullptr;
        QList<ThumbWaiter *> waiters;
        int maxPx = kDefaultMaxPx;
        QString key;
        bool started = false;
    };

    ThumbEngine() {
        m_cache.setMaxCost(kCacheCostLimit);
    }

    void pump() {
        QList<Job *> start;
        {
            QMutexLocker lock(&m_mutex);
            while (m_inFlight < kMaxInFlight && !m_queued.isEmpty()) {
                Job *job = m_queued.dequeue();
                if (!job || job->started)
                    continue;
                if (job->waiters.isEmpty()) {
                    m_jobs.remove(job->key);
                    delete job;
                    continue;
                }
                job->started = true;
                ++m_inFlight;
                start.append(job);
            }
        }
        for (Job *job : start)
            beginNetwork(job);
    }

    void beginNetwork(Job *job) {
        QNetworkRequest request(job->url);
        request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("BooruVerse/1.3-desktop"));
        request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);
        request.setTransferTimeout(15000);
        request.setPriority(job->maxPx > 800 ? QNetworkRequest::HighPriority : QNetworkRequest::LowPriority);

        QNetworkReply *reply = HttpClient::instance().network()->get(request);
        {
            QMutexLocker lock(&m_mutex);
            job->reply = reply;
        }
        QObject::connect(reply, &QNetworkReply::finished, this, [this, job, reply]() {
            finishJob(job, reply);
        });
    }

    void finishJob(Job *job, QNetworkReply *reply) {
        reply->deleteLater();

        QList<ThumbWaiter *> waiters;
        QString key;
        int maxPx = kDefaultMaxPx;
        {
            QMutexLocker lock(&m_mutex);
            waiters = job->waiters;
            key = job->key;
            maxPx = job->maxPx;
            m_jobs.remove(key);
            if (job->started)
                m_inFlight = qMax(0, m_inFlight - 1);
            delete job;
        }

        QImage image;
        QString error;
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() == QNetworkReply::OperationCanceledError) {
            error = QStringLiteral("cancelled");
        } else if (reply->error() != QNetworkReply::NoError) {
            error = reply->errorString();
        } else if (status && (status < 200 || status >= 300)) {
            error = QStringLiteral("HTTP %1").arg(status);
        } else {
            image = decodeScaled(reply->readAll(), maxPx);
            if (image.isNull()) {
                error = QStringLiteral("decode");
            } else {
                QMutexLocker lock(&m_mutex);
                m_cache.insert(key, new QImage(image), imageCost(image));
            }
        }

        for (ThumbWaiter *waiter : waiters) {
            if (!waiter->cancelled)
                waiter->complete(image, error);
            else
                waiter->complete({}, QStringLiteral("cancelled"));
        }
        pump();
    }

    QMutex m_mutex;
    QHash<QString, Job *> m_jobs;
    QQueue<Job *> m_queued;
    int m_inFlight = 0;
    QCache<QString, QImage> m_cache;
};

ThumbWaiter::~ThumbWaiter() {
    if (!m_done)
        ThumbEngine::instance().detach(this);
}

void ThumbWaiter::cancel() {
    if (cancelled || m_done)
        return;
    cancelled = true;
    ThumbEngine::instance().detach(this);
    complete({}, QStringLiteral("cancelled"));
}

} // namespace

void ThumbImageProvider::purgeCache() {
    ThumbEngine::instance().purge();
}

QQuickImageResponse *ThumbImageProvider::requestImageResponse(const QString &id, const QSize &requestedSize) {
    int maxPx = requestedSize.isValid() ? qMax(requestedSize.width(), requestedSize.height()) : kDefaultMaxPx;
    QString encoded = id;
    const int slash = id.indexOf(QLatin1Char('/'));
    if (slash > 0) {
        bool ok = false;
        const int parsed = id.left(slash).toInt(&ok);
        if (ok && parsed > 0)
            maxPx = parsed;
        encoded = id.mid(slash + 1);
    }
    const QUrl url(QUrl::fromPercentEncoding(encoded.toUtf8()));
    return ThumbEngine::instance().request(url, clampMaxPx(maxPx));
}
