#pragma once

#include <QByteArray>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QObject>
#include <QUrl>
#include <functional>

class HttpClient : public QObject {
    Q_OBJECT
public:
    using Callback = std::function<void(QByteArray data, QString error)>;
    using Progress = std::function<void(qint64 received, qint64 total)>;

    static HttpClient &instance();

    QNetworkAccessManager *network() const { return m_nam; }

    void get(const QUrl &url, const QVariantMap &query, Callback callback);
    void get(const QUrl &url, const QVariantMap &query, Callback callback, Progress progress,
             bool preferCache = true);
    void download(const QUrl &url, Callback callback, Progress progress = {});

private:
    explicit HttpClient(QObject *parent = nullptr);

    QNetworkAccessManager *m_nam = nullptr;
};
