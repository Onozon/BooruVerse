#pragma once

#include "core/Models.h"

#include <QObject>

class SavedTagSetStore : public QObject {
    Q_OBJECT
public:
    static SavedTagSetStore &instance();

    QVector<SavedTagSet> sets() const { return m_sets; }
    SavedTagSet save(const QString &name, const QStringList &tags, bool addToPersonal);
    void remove(const QString &id);
    SavedTagSet setFor(const QString &id) const;

signals:
    void changed();

private:
    explicit SavedTagSetStore(QObject *parent = nullptr);
    void load();
    void persist() const;

    QVector<SavedTagSet> m_sets;
};
