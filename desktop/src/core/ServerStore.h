#pragma once

#include "core/Models.h"

#include <QObject>
#include <QVector>

class ServerStore : public QObject {
    Q_OBJECT
public:
    static ServerStore &instance();

    QVector<BooruServer> servers() const { return m_servers; }
    QVector<BooruServer> enabledServers() const;

    void setServers(const QVector<BooruServer> &servers);
    void setEnabled(const QString &host, bool enabled);
    void setCredentials(const QString &host, const QString &userId, const QString &apiKey);
    void setColor(const QString &host, const QString &colorHex);
    bool addCustom(const QString &host, ApiFlavor flavor);
    bool removeHost(const QString &host);
    BooruServer serverFor(const QString &host) const;

    QColor colorFor(const QString &host) const;

signals:
    void changed();

private:
    explicit ServerStore(QObject *parent = nullptr);
    void load();
    void save() const;
    static QVector<BooruServer> seed();

    QVector<BooruServer> m_servers;
};
