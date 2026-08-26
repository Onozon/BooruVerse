#include "core/TagIndexStore.h"

#include "api/BooruClient.h"

#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>

TagIndexStore &TagIndexStore::instance() {
    static TagIndexStore store;
    return store;
}

TagIndexStore::TagIndexStore(QObject *parent)
    : QObject(parent) {
    load();
}

TagType TagIndexStore::typeFor(const QString &name) const {
    return m_types.value(name, TagType::General);
}

bool TagIndexStore::known(const QString &name) const {
    return m_types.contains(name);
}

void TagIndexStore::remember(const QString &name, TagType type) {
    if (name.isEmpty())
        return;
    if (m_types.value(name, TagType::General) == type && m_types.contains(name))
        return;
    m_types.insert(name, type);
    save();
    emit changed();
}

void TagIndexStore::remember(const QVector<BooruTag> &tags) {
    bool dirty = false;
    for (const BooruTag &tag : tags) {
        if (tag.name.isEmpty())
            continue;
        if (m_types.value(tag.name, TagType::General) != tag.type || !m_types.contains(tag.name)) {
            m_types.insert(tag.name, tag.type);
            dirty = true;
        }
    }
    if (!dirty)
        return;
    save();
    emit changed();
}

void TagIndexStore::applyTo(QVector<BooruTag> &tags) const {
    for (BooruTag &tag : tags)
        tag.type = typeFor(tag.name);
}

void TagIndexStore::resolve(const QStringList &names, const QVector<BooruServer> &servers) {
    QStringList missing;
    for (const QString &name : names) {
        if (!name.isEmpty() && !m_types.contains(name))
            missing.append(name);
    }
    if (missing.isEmpty() || servers.isEmpty())
        return;
    const QStringList batch = missing.mid(0, 40);
    BooruClient::fetchTagTypes(servers.first(), batch, [this](QVector<BooruTag> tags, QString) {
        remember(tags);
    });
}

void TagIndexStore::load() {
    QSettings settings;
    const QJsonObject object =
        QJsonDocument::fromJson(settings.value(QStringLiteral("tagIndex/json")).toByteArray()).object();
    for (auto it = object.begin(); it != object.end(); ++it)
        m_types.insert(it.key(), TagType(it.value().toInt()));
}

void TagIndexStore::save() const {
    QJsonObject object;
    for (auto it = m_types.cbegin(); it != m_types.cend(); ++it)
        object.insert(it.key(), int(it.value()));
    QSettings settings;
    settings.setValue(QStringLiteral("tagIndex/json"), QJsonDocument(object).toJson(QJsonDocument::Compact));
}
