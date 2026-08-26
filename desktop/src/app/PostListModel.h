#pragma once

#include "core/Models.h"

#include <QAbstractListModel>

class PostListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Role {
        ServerIdRole = Qt::UserRole + 1,
        PostIdRole,
        GlobalIdRole,
        PreviewRole,
        SampleRole,
        FileRole,
        SourceRole,
        WidthRole,
        HeightRole,
        ScoreRole,
        TagsRole,
        FileExtRole,
        DuplicateRole,
        BorderRole,
        FavoritedRole,
        AspectRole,
        SelectedRole
    };

    explicit PostListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setPosts(const QVector<BooruPost> &posts);
    void appendPosts(const QVector<BooruPost> &posts);
    void clear();
    BooruPost at(int index) const;
    QVector<BooruPost> posts() const { return m_posts; }
    void refreshFavorites();
    void refreshSelection();

signals:
    void countChanged();

private:
    QVector<BooruPost> m_posts;
};
