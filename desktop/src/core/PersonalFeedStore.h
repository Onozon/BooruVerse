#pragma once

#include "core/Models.h"

#include <QObject>
#include <QSet>

class PersonalFeedStore : public QObject {
    Q_OBJECT
public:
    static PersonalFeedStore &instance();

    bool contains(const QString &id) const;
    void setEnabled(const QString &id, bool enabled);
    void remove(const QString &id);
    QVector<SavedTagSet> personalSets() const;

signals:
    void changed();

private:
    explicit PersonalFeedStore(QObject *parent = nullptr);
    void load();
    void save() const;

    QSet<QString> m_ids;
};
