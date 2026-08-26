#include "core/ServerStore.h"

#include <algorithm>

#include <QSettings>

static const QStringList kPalette = {
    QStringLiteral("#4A90E2"), QStringLiteral("#E23B3B"), QStringLiteral("#4CB56E"),
    QStringLiteral("#F29A3D"), QStringLiteral("#A170DB"), QStringLiteral("#EB73B3"),
    QStringLiteral("#40BABA"), QStringLiteral("#D9BF3D"), QStringLiteral("#5C6BC0"),
    QStringLiteral("#26A69A")
};

ServerStore &ServerStore::instance() {
    static ServerStore store;
    return store;
}

ServerStore::ServerStore(QObject *parent)
    : QObject(parent) {
    load();
}

QVector<BooruServer> ServerStore::seed() {
    return {
        {QStringLiteral("safebooru.org"), ApiFlavor::Gelbooru, true, true, {}, {}, QStringLiteral("#4A90E2")},
        {QStringLiteral("yande.re"), ApiFlavor::Moebooru, false, true, {}, {}, QStringLiteral("#E23B3B")},
        {QStringLiteral("konachan.com"), ApiFlavor::Moebooru, false, true, {}, {}, QStringLiteral("#4CB56E")},
        {QStringLiteral("danbooru.donmai.us"), ApiFlavor::Danbooru2, false, true, {}, {}, QStringLiteral("#F29A3D")},
        {QStringLiteral("gelbooru.com"), ApiFlavor::Gelbooru, false, true, {}, {}, QStringLiteral("#A170DB")},
    };
}

void ServerStore::load() {
    QSettings settings;
    const int count = settings.beginReadArray(QStringLiteral("servers"));
    QVector<BooruServer> stored;
    for (int i = 0; i < count; ++i) {
        settings.setArrayIndex(i);
        BooruServer server;
        server.host = settings.value(QStringLiteral("host")).toString();
        server.flavor = ApiFlavor(settings.value(QStringLiteral("flavor")).toInt());
        server.enabled = settings.value(QStringLiteral("enabled")).toBool();
        server.builtIn = settings.value(QStringLiteral("builtIn")).toBool();
        server.apiKey = settings.value(QStringLiteral("apiKey")).toString();
        server.userId = settings.value(QStringLiteral("userId")).toString();
        server.colorHex = settings.value(QStringLiteral("colorHex")).toString();
        if (!server.host.isEmpty())
            stored.append(server);
    }
    settings.endArray();

    m_servers = seed();
    for (BooruServer &builtin : m_servers) {
        for (const BooruServer &item : stored) {
            if (item.host == builtin.host) {
                builtin.enabled = item.enabled;
                builtin.apiKey = item.apiKey;
                builtin.userId = item.userId;
                if (!item.colorHex.isEmpty())
                    builtin.colorHex = item.colorHex;
            }
        }
    }
    for (const BooruServer &item : stored) {
        bool known = false;
        for (const BooruServer &builtin : m_servers) {
            if (builtin.host == item.host)
                known = true;
        }
        if (!known)
            m_servers.append(item);
    }

    bool anyEnabled = false;
    for (const BooruServer &server : m_servers)
        anyEnabled = anyEnabled || server.enabled;
    if (!anyEnabled && !m_servers.isEmpty())
        m_servers[0].enabled = true;
}

void ServerStore::save() const {
    QSettings settings;
    settings.beginWriteArray(QStringLiteral("servers"), m_servers.size());
    for (int i = 0; i < m_servers.size(); ++i) {
        settings.setArrayIndex(i);
        const BooruServer &server = m_servers[i];
        settings.setValue(QStringLiteral("host"), server.host);
        settings.setValue(QStringLiteral("flavor"), int(server.flavor));
        settings.setValue(QStringLiteral("enabled"), server.enabled);
        settings.setValue(QStringLiteral("builtIn"), server.builtIn);
        settings.setValue(QStringLiteral("apiKey"), server.apiKey);
        settings.setValue(QStringLiteral("userId"), server.userId);
        settings.setValue(QStringLiteral("colorHex"), server.colorHex);
    }
    settings.endArray();
}

QVector<BooruServer> ServerStore::enabledServers() const {
    QVector<BooruServer> result;
    for (const BooruServer &server : m_servers) {
        if (server.enabled)
            result.append(server);
    }
    return result;
}

void ServerStore::setServers(const QVector<BooruServer> &servers) {
    m_servers = servers;
    save();
    emit changed();
}

void ServerStore::setEnabled(const QString &host, bool enabled) {
    if (!enabled) {
        int others = 0;
        for (const BooruServer &server : m_servers) {
            if (server.host != host && server.enabled)
                ++others;
        }
        if (others == 0)
            return;
    }
    bool found = false;
    for (BooruServer &server : m_servers) {
        if (server.host != host)
            continue;
        if (server.enabled == enabled)
            return;
        server.enabled = enabled;
        found = true;
    }
    if (!found)
        return;
    save();
    emit changed();
}

void ServerStore::setColor(const QString &host, const QString &colorHex) {
    for (BooruServer &server : m_servers) {
        if (server.host == host)
            server.colorHex = colorHex;
    }
    save();
    emit changed();
}

void ServerStore::setCredentials(const QString &host, const QString &userId, const QString &apiKey) {
    for (BooruServer &server : m_servers) {
        if (server.host == host) {
            server.userId = userId;
            server.apiKey = apiKey;
        }
    }
    save();
    emit changed();
}

bool ServerStore::addCustom(const QString &host, ApiFlavor flavor) {
    const QString normalized = host.trimmed();
    if (normalized.isEmpty())
        return false;
    for (BooruServer &server : m_servers) {
        if (server.host.compare(normalized, Qt::CaseInsensitive) == 0) {
            server.enabled = true;
            save();
            emit changed();
            return true;
        }
    }
    BooruServer server;
    server.host = normalized;
    server.flavor = flavor;
    server.enabled = true;
    server.builtIn = false;
    server.colorHex = kPalette[m_servers.size() % kPalette.size()];
    m_servers.append(server);
    save();
    emit changed();
    return true;
}

bool ServerStore::removeHost(const QString &host) {
    const auto it = std::remove_if(m_servers.begin(), m_servers.end(), [&](const BooruServer &server) {
        return !server.builtIn && server.host == host;
    });
    if (it == m_servers.end())
        return false;
    m_servers.erase(it, m_servers.end());
    save();
    emit changed();
    return true;
}

BooruServer ServerStore::serverFor(const QString &host) const {
    for (const BooruServer &server : m_servers) {
        if (server.host == host)
            return server;
    }
    return {};
}

QColor ServerStore::colorFor(const QString &host) const {
    int index = 0;
    for (const BooruServer &server : m_servers) {
        if (server.host == host) {
            if (!server.colorHex.isEmpty())
                return QColor(server.colorHex);
            return QColor(kPalette[index % kPalette.size()]);
        }
        ++index;
    }
    return QColor();
}
