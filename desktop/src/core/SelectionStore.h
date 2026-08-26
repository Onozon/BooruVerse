#pragma once

#include "core/Models.h"

#include <QAbstractListModel>
#include <QSet>

class SelectionStore : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Role {
        ServerIdRole = Qt::UserRole + 1,
        PostIdRole,
        GlobalIdRole,
        PreviewRole,
        SampleRole,
        FileRole
    };

    static SelectionStore &instance();

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool contains(const QString &globalId) const;
    Q_INVOKABLE void toggle(const BooruPost &post);
    Q_INVOKABLE void removeAt(int index);
    Q_INVOKABLE void clear();
    QVector<BooruPost> posts() const { return m_posts; }
    QVector<BooruPost> takeAll();

signals:
    void countChanged();

private:
    explicit SelectionStore(QObject *parent = nullptr);

    QVector<BooruPost> m_posts;
    QSet<QString> m_ids;
};
