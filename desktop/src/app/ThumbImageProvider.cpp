#include "app/ThumbImageProvider.h"

#include "core/HttpClient.h"

#include <QBuffer>
#include <QCache>
#include <QHash>
#include <QImage>
#include <QImageReader>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QQuickTextureFactory>
#include <QTimer>
#include <QUrl>

namespace {

QString jobKey(const QUrl &url, int maxPx) {
    return QString::number(maxPx) + QLatin1Char('|') + url.toString();
}

QImage decodeScaled(const QByteArray &data, int maxPx) {
    QBuffer buffer;
    buffer.setData(data);
    if (!buffer.open(QIODevice::ReadOnly))
        return {};
    QImageReader reader(&buffer);
    reader.setAutoTransform(true);
    QSize size = reader.size();
    if (size.isValid() && maxPx > 0) {
        const int longest = qMax(size.width(), size.height());
        if (longest > maxPx) {
            size.scale(maxPx, maxPx, Qt::KeepAspectRatio);
            reader.setScaledSize(size);
        }
    }
    return reader.read();
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
        auto *waiter = new ThumbWaiter;
        waiter->key = jobKey(url, maxPx);

        if (url.isEmpty()) {
            QTimer::singleShot(0, waiter, [waiter]() { waiter->complete({}, QStringLiteral("empty")); });
            return waiter;
        }

        if (const QImage *cached = m_cache.object(waiter->key)) {
            const QImage copy = *cached;
            QTimer::singleShot(0, waiter, [waiter, copy]() { waiter->complete(copy, {}); });
            return waiter;
        }

        Job *job = m_jobs.value(waiter->key);
        if (!job) {
            job = startJob(url, maxPx, waiter->key);
            m_jobs.insert(waiter->key, job);
        }
        job->waiters.append(waiter);
        return waiter;
    }

    void detach(ThumbWaiter *waiter) {
        if (!waiter || waiter->key.isEmpty())
            return;
        Job *job = m_jobs.value(waiter->key);
        if (!job)
            return;
        job->waiters.removeAll(waiter);
        if (!job->waiters.isEmpty() || !job->reply)
            return;
        job->reply->abort();
    }

private:
    struct Job {
        QNetworkReply *reply = nullptr;
        QList<ThumbWaiter *> waiters;
        int maxPx = 480;
        QString key;
    };

    ThumbEngine() {
        m_cache.setMaxCost(48 * 1024 * 1024);
    }

    Job *startJob(const QUrl &url, int maxPx, const QString &key) {
        auto *job = new Job;
        job->maxPx = maxPx;
        job->key = key;

        QNetworkRequest request(url);
        request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("BooruVerse/1.3-desktop"));
        request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);
        request.setTransferTimeout(15000);
        request.setPriority(maxPx > 800 ? QNetworkRequest::HighPriority : QNetworkRequest::LowPriority);

        QNetworkReply *reply = HttpClient::instance().network()->get(request);
        job->reply = reply;
        QObject::connect(reply, &QNetworkReply::finished, this, [this, job, reply]() {
            finishJob(job, reply);
        });
        return job;
    }

    void finishJob(Job *job, QNetworkReply *reply) {
        reply->deleteLater();
        const QString key = job->key;
        const QList<ThumbWaiter *> waiters = job->waiters;
        const int maxPx = job->maxPx;
        m_jobs.remove(key);
        delete job;

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
            if (image.isNull())
                error = QStringLiteral("decode");
            else
                m_cache.insert(key, new QImage(image), qMax(1, int(image.sizeInBytes())));
        }

        for (ThumbWaiter *waiter : waiters) {
            if (!waiter->cancelled)
                waiter->complete(image, error);
            else
                waiter->complete({}, QStringLiteral("cancelled"));
        }
    }

    QHash<QString, Job *> m_jobs;
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

QQuickImageResponse *ThumbImageProvider::requestImageResponse(const QString &id, const QSize &requestedSize) {
    const int slash = id.indexOf(QLatin1Char('/'));
    int maxPx = requestedSize.isValid() ? qMax(requestedSize.width(), requestedSize.height()) : 480;
    QString encoded = id;
    if (slash > 0) {
        bool ok = false;
        const int parsed = id.left(slash).toInt(&ok);
        if (ok && parsed > 0)
            maxPx = parsed;
        encoded = id.mid(slash + 1);
    }
    const QUrl url(QUrl::fromPercentEncoding(encoded.toUtf8()));
    return ThumbEngine::instance().request(url, qMax(maxPx, 1));
}
