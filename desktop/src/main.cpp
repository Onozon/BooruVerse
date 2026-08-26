#include "app/AppController.h"
#include "app/IconImageProvider.h"
#include "app/ThumbImageProvider.h"
#include "app/UiTheme.h"

#include <QGuiApplication>
#include <QIcon>
#include <QNetworkAccessManager>
#include <QNetworkDiskCache>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQmlNetworkAccessManagerFactory>
#include <QQuickStyle>
#include <QStandardPaths>

namespace {

class AppNam : public QNetworkAccessManager {
public:
    using QNetworkAccessManager::QNetworkAccessManager;

protected:
    QNetworkReply *createRequest(Operation op, const QNetworkRequest &request, QIODevice *outgoing) override {
        QNetworkRequest tagged = request;
        tagged.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("BooruVerse/1.3-desktop"));
        return QNetworkAccessManager::createRequest(op, tagged, outgoing);
    }
};

class CacheNamFactory : public QQmlNetworkAccessManagerFactory {
public:
    QNetworkAccessManager *create(QObject *parent) override {
        auto *nam = new AppNam(parent);
        auto *cache = new QNetworkDiskCache(nam);
        cache->setCacheDirectory(QStandardPaths::writableLocation(QStandardPaths::CacheLocation)
                                 + QStringLiteral("/http"));
        cache->setMaximumCacheSize(512 * 1024 * 1024);
        nam->setCache(cache);
        return nam;
    }
};

} // namespace

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("BooruVerse"));
    app.setOrganizationName(QStringLiteral("Onozon"));
    app.setApplicationVersion(QStringLiteral("1.3.0"));
    app.setWindowIcon(QIcon(QStringLiteral(":/icons/booruverse.png")));
    QQuickStyle::setStyle(QStringLiteral("Basic"));

    AppController controller;
    UiTheme theme;
    QQmlApplicationEngine engine;
    engine.setNetworkAccessManagerFactory(new CacheNamFactory);
    engine.rootContext()->setContextProperty(QStringLiteral("App"), &controller);
    engine.rootContext()->setContextProperty(QStringLiteral("Theme"), &theme);
    engine.addImageProvider(QStringLiteral("thumbs"), new ThumbImageProvider);
    engine.addImageProvider(QStringLiteral("uiicons"), new IconImageProvider);
    QObject::connect(
        &engine, &QQmlApplicationEngine::objectCreationFailed, &app,
        []() { QCoreApplication::exit(1); }, Qt::QueuedConnection);
    engine.loadFromModule(QStringLiteral("BooruVerse"), QStringLiteral("Main"));
    if (engine.rootObjects().isEmpty())
        return 1;
    return app.exec();
}
