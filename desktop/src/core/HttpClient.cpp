#include "core/HttpClient.h"

#include <QNetworkDiskCache>
#include <QNetworkRequest>
#include <QStandardPaths>
#include <QUrlQuery>

HttpClient &HttpClient::instance() {
    static HttpClient client;
    return client;
}

HttpClient::HttpClient(QObject *parent)
    : QObject(parent)
    , m_nam(new QNetworkAccessManager(this)) {
    auto *cache = new QNetworkDiskCache(this);
    cache->setCacheDirectory(QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
                             + QStringLiteral("/http"));
    cache->setMaximumCacheSize(512 * 1024 * 1024);
    m_nam->setCache(cache);
}

void HttpClient::get(const QUrl &url, const QVariantMap &query, Callback callback) {
    get(url, query, callback, {}, true);
}

void HttpClient::get(const QUrl &url, const QVariantMap &query, Callback callback, Progress progress,
                     bool preferCache) {
    QUrl full = url;
    QUrlQuery q(full);
    for (auto it = query.cbegin(); it != query.cend(); ++it) {
        const QString value = it.value().toString();
        if (!value.isEmpty())
            q.addQueryItem(it.key(), value);
    }
    full.setQuery(q);

    QNetworkRequest request(full);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("BooruVerse/1.3-desktop"));
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute,
                         preferCache ? QNetworkRequest::PreferCache : QNetworkRequest::AlwaysNetwork);
    request.setTransferTimeout(30000);

    QNetworkReply *reply = m_nam->get(request);
    if (progress) {
        connect(reply, &QNetworkReply::downloadProgress, this,
                [progress](qint64 received, qint64 total) { progress(received, total); });
    }
    connect(reply, &QNetworkReply::finished, this, [reply, callback]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            callback({}, reply->errorString());
            return;
        }
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status < 200 || status >= 300) {
            callback({}, QStringLiteral("HTTP %1").arg(status));
            return;
        }
        callback(reply->readAll(), {});
    });
}

void HttpClient::download(const QUrl &url, Callback callback, Progress progress) {
    QNetworkRequest request(url);
    request.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("BooruVerse/1.3-desktop"));
    request.setAttribute(QNetworkRequest::CacheLoadControlAttribute, QNetworkRequest::AlwaysNetwork);
    request.setTransferTimeout(0);

    QNetworkReply *reply = m_nam->get(request);
    if (progress) {
        connect(reply, &QNetworkReply::downloadProgress, this,
                [progress](qint64 received, qint64 total) { progress(received, total); });
    }
    connect(reply, &QNetworkReply::finished, this, [reply, callback]() {
        reply->deleteLater();
        if (reply->error() != QNetworkReply::NoError) {
            callback({}, reply->errorString());
            return;
        }
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (status < 200 || status >= 300) {
            callback({}, QStringLiteral("HTTP %1").arg(status));
            return;
        }
        callback(reply->readAll(), {});
    });
}
