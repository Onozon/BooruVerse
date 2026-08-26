#include "core/SavedTagSetStore.h"

#include "core/PersonalFeedStore.h"

#include <algorithm>

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>
#include <QUuid>

static SavedTagSet fromJson(const QJsonObject &object) {
    SavedTagSet set;
    set.id = object.value(QStringLiteral("id")).toString();
    set.name = object.value(QStringLiteral("name")).toString();
    for (const QJsonValue &value : object.value(QStringLiteral("tags")).toArray())
        set.tags.append(value.toString());
    set.createdAt = qint64(object.value(QStringLiteral("createdAt")).toDouble());
    return set;
}

static QJsonObject toJson(const SavedTagSet &set) {
    QJsonObject object;
    object.insert(QStringLiteral("id"), set.id);
    object.insert(QStringLiteral("name"), set.name);
    QJsonArray tags;
    for (const QString &tag : set.tags)
        tags.append(tag);
    object.insert(QStringLiteral("tags"), tags);
    object.insert(QStringLiteral("createdAt"), double(set.createdAt));
    return object;
}

SavedTagSetStore &SavedTagSetStore::instance() {
    static SavedTagSetStore store;
    return store;
}

SavedTagSetStore::SavedTagSetStore(QObject *parent)
    : QObject(parent) {
    load();
}

SavedTagSet SavedTagSetStore::save(const QString &name, const QStringList &tags, bool addToPersonal) {
    const QString trimmed = name.trimmed();
    SavedTagSet set;
    if (trimmed.isEmpty() || tags.isEmpty())
        return set;
    set.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    set.name = trimmed;
    set.tags = tags;
    set.createdAt = QDateTime::currentSecsSinceEpoch();
    m_sets.prepend(set);
    persist();
    if (addToPersonal)
        PersonalFeedStore::instance().setEnabled(set.id, true);
    emit changed();
    return set;
}

void SavedTagSetStore::remove(const QString &id) {
    const auto it = std::remove_if(m_sets.begin(), m_sets.end(),
                                   [&](const SavedTagSet &set) { return set.id == id; });
    if (it == m_sets.end())
        return;
    m_sets.erase(it, m_sets.end());
    persist();
    PersonalFeedStore::instance().remove(id);
    emit changed();
}

SavedTagSet SavedTagSetStore::setFor(const QString &id) const {
    for (const SavedTagSet &set : m_sets) {
        if (set.id == id)
            return set;
    }
    return {};
}

void SavedTagSetStore::load() {
    QSettings settings;
    const QJsonArray array =
        QJsonDocument::fromJson(settings.value(QStringLiteral("savedTagSets/json")).toByteArray()).array();
    for (const QJsonValue &value : array) {
        const SavedTagSet set = fromJson(value.toObject());
        if (!set.id.isEmpty() && !set.tags.isEmpty())
            m_sets.append(set);
    }
}

void SavedTagSetStore::persist() const {
    QJsonArray array;
    for (const SavedTagSet &set : m_sets)
        array.append(toJson(set));
    QSettings settings;
    settings.setValue(QStringLiteral("savedTagSets/json"), QJsonDocument(array).toJson(QJsonDocument::Compact));
}
