#include "core/PersonalFeedStore.h"

#include "core/SavedTagSetStore.h"

#include <QSettings>

PersonalFeedStore &PersonalFeedStore::instance() {
    static PersonalFeedStore store;
    return store;
}

PersonalFeedStore::PersonalFeedStore(QObject *parent)
    : QObject(parent) {
    load();
}

bool PersonalFeedStore::contains(const QString &id) const {
    return m_ids.contains(id);
}

void PersonalFeedStore::setEnabled(const QString &id, bool enabled) {
    if (id.isEmpty())
        return;
    if (enabled)
        m_ids.insert(id);
    else
        m_ids.remove(id);
    save();
    emit changed();
}

void PersonalFeedStore::remove(const QString &id) {
    if (!m_ids.remove(id))
        return;
    save();
    emit changed();
}

QVector<SavedTagSet> PersonalFeedStore::personalSets() const {
    QVector<SavedTagSet> result;
    for (const SavedTagSet &set : SavedTagSetStore::instance().sets()) {
        if (m_ids.contains(set.id))
            result.append(set);
    }
    return result;
}

void PersonalFeedStore::load() {
    QSettings settings;
    const QStringList ids = settings.value(QStringLiteral("personalFeed/selectedSetIDs")).toStringList();
    m_ids = QSet<QString>(ids.begin(), ids.end());
}

void PersonalFeedStore::save() const {
    QSettings settings;
    settings.setValue(QStringLiteral("personalFeed/selectedSetIDs"), QStringList(m_ids.values()));
}
