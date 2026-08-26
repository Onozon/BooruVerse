#include "app/ThumbImageProvider.h"

#include "core/HttpClient.h"

#include <QBuffer>
#include <QCache>
#include <QCoreApplication>
#include <QHash>
#include <QImage>
#include <QImageReader>
#include <QMetaObject>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QPointer>
#include <QQuickTextureFactory>
#include <QQueue>
#include <QThread>
#include <QThreadPool>
#include <QUrl>

#include <atomic>

namespace {

constexpr int kDefaultMaxPx = 480;
constexpr int kHardMaxPx = 1600;
constexpr int kCacheCostLimit = 32 * 1024 * 1024;
constexpr int kMaxInFlight = 5;

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

class ThumbWaiter final : public QQuickImageResponse {
public:
    ~ThumbWaiter() override;
    void cancel() override;
    QQuickTextureFactory *textureFactory() const override {
        return m_image.isNull() ? nullptr : QQuickTextureFactory::textureFactoryForImage(m_image);
    }
    QString errorString() const override { return m_error; }

    void complete(const QImage &image, const QString &error) {
        if (m_done.exchange(true))
            return;
        m_image = image;
        m_error = error;
        Q_EMIT finished();
    }

    QString key;
    std::atomic_bool cancelled{false};

private:
    QImage m_image;
    QString m_error;
    std::atomic_bool m_done{false};
};

class ThumbEngine final : public QObject {
    Q_OBJECT
public:
    static ThumbEngine *s_instance;

    static ThumbEngine &instance() {
        Q_ASSERT(s_instance);
        return *s_instance;
    }

    static void ensure() {
        Q_ASSERT(QCoreApplication::instance());
        Q_ASSERT(QThread::currentThread() == QCoreApplication::instance()->thread());
        if (!s_instance)
            s_instance = new ThumbEngine(QCoreApplication::instance());
    }

    QQuickImageResponse *request(const QUrl &url, int maxPx) {
        maxPx = clampMaxPx(maxPx);
        auto *waiter = new ThumbWaiter;
        waiter->key = jobKey(url, maxPx);

        if (url.isEmpty()) {
            QMetaObject::invokeMethod(
                this, [waiter]() { waiter->complete({}, QStringLiteral("empty")); }, Qt::QueuedConnection);
            return waiter;
        }

        // QQuickAsyncImageProvider may call us from QQuickPixmapReader's thread.
        // Never touch QNetworkAccessManager off the GUI thread — that freezes the app.
        QMetaObject::invokeMethod(
            this,
            [this, waiter = QPointer<ThumbWaiter>(waiter), url, maxPx, key = waiter->key]() {
                if (!waiter || waiter->cancelled)
                    return;
                handleRequest(waiter.data(), url, maxPx, key);
            },
            Qt::QueuedConnection);
        return waiter;
    }

    void dropWaiter(ThumbWaiter *waiter) {
        if (!waiter)
            return;
        // Capture key before any queued hop — waiter may be destroyed by then.
        const QString key = waiter->key;
        const QPointer<ThumbWaiter> guard(waiter);
        if (QThread::currentThread() != thread()) {
            QMetaObject::invokeMethod(this, [this, key, guard]() { dropWaiterOnMain(key, guard); },
                                      Qt::QueuedConnection);
            return;
        }
        dropWaiterOnMain(key, guard);
    }

    void dropWaiterOnMain(const QString &key, const QPointer<ThumbWaiter> &guard) {
        Job *job = m_jobs.value(key);
        if (!job)
            return;
        if (guard)
            job->waiters.removeAll(guard);
        job->waiters.removeAll(nullptr);
        if (!job->waiters.isEmpty())
            return;
        if (job->reply) {
            job->reply->abort();
            return;
        }
        // Decode may already be running without a Job entry; nothing to abort here.
        m_queued.removeAll(job);
        m_jobs.remove(job->key);
        delete job;
    }

    void purge() {
        if (QThread::currentThread() != thread()) {
            QMetaObject::invokeMethod(this, &ThumbEngine::purge, Qt::QueuedConnection);
            return;
        }
        m_cache.clear();
    }

    void deliverDecoded(const QString &key, const QImage &image, const QString &error,
                        const QList<QPointer<ThumbWaiter>> &waiters) {
        bool anyLive = false;
        for (const QPointer<ThumbWaiter> &waiter : waiters) {
            if (waiter && !waiter->cancelled)
                anyLive = true;
        }
        if (!image.isNull() && anyLive)
            m_cache.insert(key, new QImage(image), imageCost(image));

        for (const QPointer<ThumbWaiter> &waiter : waiters) {
            if (!waiter)
                continue;
            if (waiter->cancelled)
                waiter->complete({}, QStringLiteral("cancelled"));
            else
                waiter->complete(image, error);
        }

        m_inFlight = qMax(0, m_inFlight - 1);
        pump();
    }

private:
    struct Job {
        QUrl url;
        QNetworkReply *reply = nullptr;
        QList<QPointer<ThumbWaiter>> waiters;
        int maxPx = kDefaultMaxPx;
        QString key;
        bool started = false;
    };

    explicit ThumbEngine(QObject *parent)
        : QObject(parent) {
        m_cache.setMaxCost(kCacheCostLimit);
    }

    void handleRequest(ThumbWaiter *waiter, const QUrl &url, int maxPx, const QString &key) {
        if (!waiter || waiter->cancelled)
            return;

        if (const QImage *cached = m_cache.object(key)) {
            waiter->complete(*cached, {});
            return;
        }

        Job *job = m_jobs.value(key);
        if (!job) {
            job = new Job;
            job->url = url;
            job->maxPx = maxPx;
            job->key = key;
            m_jobs.insert(key, job);
            m_queued.enqueue(job);
        }
        job->waiters.append(waiter);
        pump();
    }

    void pump() {
        while (m_inFlight < kMaxInFlight && !m_queued.isEmpty()) {
            Job *job = m_queued.dequeue();
            if (!job || job->started)
                continue;
            job->waiters.removeAll(nullptr);
            if (job->waiters.isEmpty()) {
                m_jobs.remove(job->key);
                delete job;
                continue;
            }
            job->started = true;
            ++m_inFlight;
            beginNetwork(job);
        }
    }

    void beginNetwork(Job *job) {
        QNetworkRequest request(job->url);
        request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("BooruVerse/1.3-desktop"));
        request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::PreferCache);
        request.setTransferTimeout(15000);
        request.setPriority(job->maxPx > 800 ? QNetworkRequest::HighPriority : QNetworkRequest::NormalPriority);

        QNetworkReply *reply = HttpClient::instance().network()->get(request);
        job->reply = reply;
        connect(reply, &QNetworkReply::finished, this, [this, job, reply]() { finishNetwork(job, reply); });
    }

    void finishNetwork(Job *job, QNetworkReply *reply) {
        reply->deleteLater();

        const QList<QPointer<ThumbWaiter>> waiters = job->waiters;
        const QString key = job->key;
        const int maxPx = job->maxPx;
        m_jobs.remove(key);
        delete job;

        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() == QNetworkReply::OperationCanceledError) {
            completeWaiters(waiters, {}, QStringLiteral("cancelled"));
            m_inFlight = qMax(0, m_inFlight - 1);
            pump();
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            completeWaiters(waiters, {}, reply->errorString());
            m_inFlight = qMax(0, m_inFlight - 1);
            pump();
            return;
        }
        if (status && (status < 200 || status >= 300)) {
            completeWaiters(waiters, {}, QStringLiteral("HTTP %1").arg(status));
            m_inFlight = qMax(0, m_inFlight - 1);
            pump();
            return;
        }

        const QByteArray bytes = reply->readAll();
        // Keep m_inFlight reserved through decode so scroll storms cannot pile up.
        QThreadPool::globalInstance()->start([this, key, bytes, maxPx, waiters]() {
            const QImage image = decodeScaled(bytes, maxPx);
            const QString error = image.isNull() ? QStringLiteral("decode") : QString();
            QMetaObject::invokeMethod(
                this,
                [this, key, image, error, waiters]() { deliverDecoded(key, image, error, waiters); },
                Qt::QueuedConnection);
        });
    }

    static void completeWaiters(const QList<QPointer<ThumbWaiter>> &waiters, const QImage &image,
                                const QString &error) {
        for (const QPointer<ThumbWaiter> &waiter : waiters) {
            if (!waiter)
                continue;
            if (waiter->cancelled)
                waiter->complete({}, QStringLiteral("cancelled"));
            else
                waiter->complete(image, error);
        }
    }

    QHash<QString, Job *> m_jobs;
    QQueue<Job *> m_queued;
    int m_inFlight = 0;
    QCache<QString, QImage> m_cache;
};

ThumbWaiter::~ThumbWaiter() {
    if (!m_done) {
        cancelled = true;
        ThumbEngine::instance().dropWaiter(this);
    }
}

void ThumbWaiter::cancel() {
    if (cancelled.exchange(true) || m_done)
        return;
    ThumbEngine::instance().dropWaiter(this);
    complete({}, QStringLiteral("cancelled"));
}

} // namespace

ThumbEngine *ThumbEngine::s_instance = nullptr;

void ThumbImageProvider::ensureEngine() {
    ThumbEngine::ensure();
}

void ThumbImageProvider::purgeCache() {
    if (ThumbEngine::s_instance)
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

#include "ThumbImageProvider.moc"
