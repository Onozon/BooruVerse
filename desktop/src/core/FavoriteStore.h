#pragma once

#include "core/Models.h"

#include <QObject>
#include <QSet>
#include <QUuid>

class FavoriteStore : public QObject {
    Q_OBJECT
public:
    static FavoriteStore &instance();

    bool contains(const QString &globalId) const;
    void unfavorite(const QString &globalId);
    void addToFolder(const BooruPost &post, const QString &folderId);
    void addMany(const QVector<BooruPost> &posts, const QString &folderId);
    void updateSnapshot(const BooruPost &post);
    QVector<BooruPost> posts() const;
    QVector<BooruPost> postsInFolder(const QString &folderId) const;

    QVector<FavoriteFolder> folders() const { return m_folders; }
    QString lastFolderId() const { return m_lastFolderId; }
    QString createFolder(const QString &name);
    void renameFolder(const QString &id, const QString &name);
    void deleteFolder(const QString &id, bool deletePosts);
    FavoriteFolder folder(const QString &id) const;

signals:
    void changed();

private:
    explicit FavoriteStore(QObject *parent = nullptr);
    void load();
    void save() const;
    void ensureDefaultFolder();

    QVector<BooruPost> m_posts;
    QSet<QString> m_ids;
    QVector<FavoriteFolder> m_folders;
    QString m_lastFolderId;
};
