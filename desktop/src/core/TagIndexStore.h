#pragma once

#include "core/Models.h"

#include <QHash>
#include <QObject>

class TagIndexStore : public QObject {
    Q_OBJECT
public:
    static TagIndexStore &instance();

    TagType typeFor(const QString &name) const;
    bool known(const QString &name) const;
    void remember(const QString &name, TagType type);
    void remember(const QVector<BooruTag> &tags);
    void applyTo(QVector<BooruTag> &tags) const;
    void resolve(const QStringList &names, const QVector<BooruServer> &servers);

signals:
    void changed();

private:
    explicit TagIndexStore(QObject *parent = nullptr);
    void load();
    void save() const;

    QHash<QString, TagType> m_types;
};
