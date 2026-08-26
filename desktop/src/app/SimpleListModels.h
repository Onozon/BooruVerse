#pragma once

#include "core/Models.h"

#include <QAbstractListModel>
#include <QVariant>

class TagListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Role { NameRole = Qt::UserRole + 1, CountRole, TypeRole, TypeTitleRole, ColorRole, SelectedRole };

    explicit TagListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    void setTags(const QVector<BooruTag> &tags, const QStringList &selected = {});
    void setSelected(const QStringList &selected);
    QString nameAt(int index) const;
    Q_INVOKABLE QVariantMap tagAt(int index) const;

signals:
    void countChanged();

private:
    QVector<BooruTag> m_tags;
    QStringList m_selected;
};

class ServerListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Role {
        HostRole = Qt::UserRole + 1,
        FlavorRole,
        FlavorTitleRole,
        EnabledRole,
        BuiltInRole,
        UserRole,
        ApiKeyRole,
        ColorRole,
        ShowKeyRole,
        KeyDangerRole,
        CredentialTitleRole
    };

    explicit ServerListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void reload();
    BooruServer at(int index) const;
    Q_INVOKABLE QVariantMap serverAt(int index) const;

signals:
    void countChanged();

private:
    QVector<BooruServer> m_servers;
};

class PoolListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Role {
        ServerIdRole = Qt::UserRole + 1,
        PoolIdRole,
        NameRole,
        CountRole,
        DescriptionRole,
        ColorRole,
        PreviewUrlsRole
    };

    explicit PoolListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void setPools(const QVector<BooruPool> &pools);
    void appendPools(const QVector<BooruPool> &pools);
    void setPreviewUrls(int row, const QStringList &urls);
    void clear();
    BooruPool at(int index) const;

signals:
    void countChanged();

private:
    QVector<BooruPool> m_pools;
    QVector<QStringList> m_previews;
};

class FolderListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Role { IdRole = Qt::UserRole + 1, NameRole, DefaultRole, CountRole };

    explicit FolderListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void reload();
    FavoriteFolder at(int index) const;
    Q_INVOKABLE QVariantMap folderAt(int index) const;
    Q_INVOKABLE int indexOfId(const QString &id) const;

signals:
    void countChanged();

private:
    QVector<FavoriteFolder> m_folders;
};

class SavedSetListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
public:
    enum Role { IdRole = Qt::UserRole + 1, NameRole, TagsRole, JoinedRole, InPersonalRole };

    explicit SavedSetListModel(QObject *parent = nullptr);

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    void reload();
    SavedTagSet at(int index) const;

signals:
    void countChanged();

private:
    QVector<SavedTagSet> m_sets;
};
