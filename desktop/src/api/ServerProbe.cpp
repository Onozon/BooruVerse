#include "api/ServerProbe.h"

#include "core/HttpClient.h"

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>

QString ServerProbe::normalizeHost(QString host) {
    host = host.trimmed();
    host.remove(QRegularExpression(QStringLiteral("^https?://"), QRegularExpression::CaseInsensitiveOption));
    if (host.endsWith(QLatin1Char('/')))
        host.chop(1);
    return host;
}

void ServerProbe::detect(const QString &host, Callback callback) {
    const QString normalized = normalizeHost(host);
    if (normalized.isEmpty()) {
        callback(false, ApiFlavor::Moebooru, QStringLiteral("Enter a host."));
        return;
    }
    const QUrl base(QStringLiteral("https://") + normalized);

    auto fail = [callback]() {
        callback(false, ApiFlavor::Moebooru, QStringLiteral("This host doesn't look like a supported booru API."));
    };

    HttpClient::instance().get(base.resolved(QUrl(QStringLiteral("/post.json"))),
                               {{QStringLiteral("limit"), QStringLiteral("1")}},
                               [=](QByteArray data, QString error) {
        if (error.isEmpty()) {
            const QJsonDocument document = QJsonDocument::fromJson(data);
            if (document.isArray()) {
                callback(true, ApiFlavor::Moebooru, {});
                return;
            }
        }
        HttpClient::instance().get(base.resolved(QUrl(QStringLiteral("/posts.json"))),
                                   {{QStringLiteral("limit"), QStringLiteral("1")}},
                                   [=](QByteArray data, QString error) {
            if (error.isEmpty()) {
                const QJsonDocument document = QJsonDocument::fromJson(data);
                if (document.isArray()) {
                    const QJsonObject first = document.array().isEmpty()
                        ? QJsonObject()
                        : document.array().first().toObject();
                    if (document.array().isEmpty() || first.contains(QStringLiteral("tag_string"))
                        || first.contains(QStringLiteral("file_ext"))) {
                        callback(true, ApiFlavor::Danbooru2, {});
                        return;
                    }
                }
            }
            HttpClient::instance().get(
                base.resolved(QUrl(QStringLiteral("/index.php"))),
                {{QStringLiteral("page"), QStringLiteral("dapi")},
                 {QStringLiteral("s"), QStringLiteral("post")},
                 {QStringLiteral("q"), QStringLiteral("index")},
                 {QStringLiteral("json"), QStringLiteral("1")},
                 {QStringLiteral("limit"), QStringLiteral("1")}},
                [=](QByteArray data, QString error) {
                    if (error.isEmpty()) {
                        const QJsonDocument document = QJsonDocument::fromJson(data);
                        if (document.isObject()
                            && (document.object().contains(QStringLiteral("post"))
                                || document.object().contains(QStringLiteral("@attributes")))) {
                            callback(true, ApiFlavor::Gelbooru, {});
                            return;
                        }
                        if (document.isArray()) {
                            callback(true, ApiFlavor::Gelbooru, {});
                            return;
                        }
                    }
                    fail();
                });
        });
    });
}
