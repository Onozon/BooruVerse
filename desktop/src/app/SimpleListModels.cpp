#include "app/SimpleListModels.h"

#include "core/FavoriteStore.h"
#include "core/PersonalFeedStore.h"
#include "core/SavedTagSetStore.h"
#include "core/ServerStore.h"

TagListModel::TagListModel(QObject *parent)
    : QAbstractListModel(parent) {
}

int TagListModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_tags.size();
}

QVariant TagListModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_tags.size())
        return {};
    const BooruTag &tag = m_tags[index.row()];
    switch (role) {
    case NameRole:
        return tag.name;
    case CountRole:
        return tag.postCount;
    case TypeRole:
        return int(tag.type);
    case TypeTitleRole:
        return tagTypeTitle(tag.type);
    case ColorRole:
        return tagTypeColor(tag.type).name();
    case SelectedRole:
        return m_selected.contains(tag.name, Qt::CaseInsensitive);
    default:
        return {};
    }
}

QHash<int, QByteArray> TagListModel::roleNames() const {
    return {{NameRole, "name"},     {CountRole, "postCount"}, {TypeRole, "type"},
            {TypeTitleRole, "typeTitle"}, {ColorRole, "typeColor"}, {SelectedRole, "selected"}};
}

void TagListModel::setTags(const QVector<BooruTag> &tags, const QStringList &selected) {
    beginResetModel();
    m_tags = tags;
    m_selected = selected;
    endResetModel();
    emit countChanged();
}

void TagListModel::setSelected(const QStringList &selected) {
    if (m_selected == selected)
        return;
    m_selected = selected;
    if (m_tags.isEmpty())
        return;
    emit dataChanged(index(0), index(m_tags.size() - 1), {SelectedRole});
}

QString TagListModel::nameAt(int index) const {
    return (index >= 0 && index < m_tags.size()) ? m_tags[index].name : QString();
}

QVariantMap TagListModel::tagAt(int index) const {
    if (index < 0 || index >= m_tags.size())
        return {};
    const BooruTag &tag = m_tags[index];
    return {{QStringLiteral("name"), tag.name},
            {QStringLiteral("postCount"), tag.postCount},
            {QStringLiteral("type"), int(tag.type)},
            {QStringLiteral("typeTitle"), tagTypeTitle(tag.type)},
            {QStringLiteral("typeColor"), tagTypeColor(tag.type).name()},
            {QStringLiteral("selected"), m_selected.contains(tag.name, Qt::CaseInsensitive)}};
}

ServerListModel::ServerListModel(QObject *parent)
    : QAbstractListModel(parent) {
    reload();
}

int ServerListModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_servers.size();
}

QVariant ServerListModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_servers.size())
        return {};
    const BooruServer &server = m_servers[index.row()];
    switch (role) {
    case HostRole:
        return server.host;
    case FlavorRole:
        return int(server.flavor);
    case FlavorTitleRole:
        return flavorTitle(server.flavor);
    case EnabledRole:
        return server.enabled;
    case BuiltInRole:
        return server.builtIn;
    case UserRole:
        return server.userId;
    case ApiKeyRole:
        return server.apiKey;
    case ColorRole:
        return ServerStore::instance().colorFor(server.host).name();
    case ShowKeyRole:
        return server.supportsCredentials() && !server.hasCredentials();
    case KeyDangerRole:
        return server.requiresCredentials();
    case CredentialTitleRole:
        return server.credentialUserTitle();
    default:
        return {};
    }
}

QHash<int, QByteArray> ServerListModel::roleNames() const {
    return {{HostRole, "host"},           {FlavorRole, "flavor"},     {FlavorTitleRole, "flavorTitle"},
            {EnabledRole, "enabled"},     {BuiltInRole, "builtIn"},   {UserRole, "userId"},
            {ApiKeyRole, "apiKey"},       {ColorRole, "colorHex"},    {ShowKeyRole, "showKey"},
            {KeyDangerRole, "keyDanger"}, {CredentialTitleRole, "credentialTitle"}};
}

void ServerListModel::reload() {
    beginResetModel();
    m_servers = ServerStore::instance().servers();
    endResetModel();
    emit countChanged();
}

BooruServer ServerListModel::at(int index) const {
    return (index >= 0 && index < m_servers.size()) ? m_servers[index] : BooruServer{};
}

QVariantMap ServerListModel::serverAt(int index) const {
    if (index < 0 || index >= m_servers.size())
        return {};
    const BooruServer &server = m_servers[index];
    return {{QStringLiteral("host"), server.host},
            {QStringLiteral("flavor"), int(server.flavor)},
            {QStringLiteral("flavorTitle"), flavorTitle(server.flavor)},
            {QStringLiteral("enabled"), server.enabled},
            {QStringLiteral("builtIn"), server.builtIn},
            {QStringLiteral("userId"), server.userId},
            {QStringLiteral("apiKey"), server.apiKey},
            {QStringLiteral("colorHex"), ServerStore::instance().colorFor(server.host).name()},
            {QStringLiteral("showKey"), server.supportsCredentials() && !server.hasCredentials()},
            {QStringLiteral("keyDanger"), server.requiresCredentials()},
            {QStringLiteral("credentialTitle"), server.credentialUserTitle()}};
}

PoolListModel::PoolListModel(QObject *parent)
    : QAbstractListModel(parent) {
}

int PoolListModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_pools.size();
}

QVariant PoolListModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_pools.size())
        return {};
    const BooruPool &pool = m_pools[index.row()];
    switch (role) {
    case ServerIdRole:
        return pool.serverId;
    case PoolIdRole:
        return pool.id;
    case NameRole:
        return pool.displayName();
    case CountRole:
        return pool.postCount;
    case DescriptionRole:
        return pool.description;
    case ColorRole:
        return ServerStore::instance().colorFor(pool.serverId).name();
    case PreviewUrlsRole:
        return (index.row() < m_previews.size()) ? QVariant(m_previews[index.row()]) : QVariant(QStringList{});
    default:
        return {};
    }
}

QHash<int, QByteArray> PoolListModel::roleNames() const {
    return {{ServerIdRole, "serverId"}, {PoolIdRole, "poolId"},     {NameRole, "name"},
            {CountRole, "postCount"},   {DescriptionRole, "description"}, {ColorRole, "colorHex"},
            {PreviewUrlsRole, "previewUrls"}};
}

void PoolListModel::setPools(const QVector<BooruPool> &pools) {
    beginResetModel();
    m_pools = pools;
    m_previews = QVector<QStringList>(pools.size());
    endResetModel();
    emit countChanged();
}

void PoolListModel::appendPools(const QVector<BooruPool> &pools) {
    if (pools.isEmpty())
        return;
    const int start = m_pools.size();
    beginInsertRows({}, start, start + pools.size() - 1);
    m_pools += pools;
    m_previews.resize(m_pools.size());
    endInsertRows();
    emit countChanged();
}

void PoolListModel::setPreviewUrls(int row, const QStringList &urls) {
    if (row < 0 || row >= m_previews.size())
        return;
    m_previews[row] = urls;
    emit dataChanged(index(row), index(row), {PreviewUrlsRole});
}

void PoolListModel::clear() {
    beginResetModel();
    m_pools.clear();
    m_previews.clear();
    endResetModel();
    emit countChanged();
}

BooruPool PoolListModel::at(int index) const {
    return (index >= 0 && index < m_pools.size()) ? m_pools[index] : BooruPool{};
}

SavedSetListModel::SavedSetListModel(QObject *parent)
    : QAbstractListModel(parent) {
    reload();
}

int SavedSetListModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_sets.size();
}

QVariant SavedSetListModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_sets.size())
        return {};
    const SavedTagSet &set = m_sets[index.row()];
    switch (role) {
    case IdRole:
        return set.id;
    case NameRole:
        return set.name;
    case TagsRole:
        return set.tags;
    case JoinedRole:
        return set.joined();
    case InPersonalRole:
        return PersonalFeedStore::instance().contains(set.id);
    default:
        return {};
    }
}

QHash<int, QByteArray> SavedSetListModel::roleNames() const {
    return {{IdRole, "setId"}, {NameRole, "name"}, {TagsRole, "tags"},
            {JoinedRole, "joined"}, {InPersonalRole, "inPersonal"}};
}

void SavedSetListModel::reload() {
    beginResetModel();
    m_sets = SavedTagSetStore::instance().sets();
    endResetModel();
    emit countChanged();
}

SavedTagSet SavedSetListModel::at(int index) const {
    return (index >= 0 && index < m_sets.size()) ? m_sets[index] : SavedTagSet{};
}

FolderListModel::FolderListModel(QObject *parent)
    : QAbstractListModel(parent) {
    reload();
}

int FolderListModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_folders.size();
}

QVariant FolderListModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_folders.size())
        return {};
    const FavoriteFolder &folder = m_folders[index.row()];
    switch (role) {
    case IdRole:
        return folder.id;
    case NameRole:
        return folder.name;
    case DefaultRole:
        return folder.id == defaultFavoriteFolderId();
    case CountRole:
        return FavoriteStore::instance().postsInFolder(folder.id).size();
    default:
        return {};
    }
}

QHash<int, QByteArray> FolderListModel::roleNames() const {
    return {{IdRole, "folderId"}, {NameRole, "name"}, {DefaultRole, "isDefault"}, {CountRole, "postCount"}};
}

void FolderListModel::reload() {
    beginResetModel();
    m_folders = FavoriteStore::instance().folders();
    endResetModel();
    emit countChanged();
}

FavoriteFolder FolderListModel::at(int index) const {
    return (index >= 0 && index < m_folders.size()) ? m_folders[index] : FavoriteFolder{};
}

QVariantMap FolderListModel::folderAt(int index) const {
    const FavoriteFolder folder = at(index);
    if (folder.id.isEmpty())
        return {};
    return {{QStringLiteral("id"), folder.id},
            {QStringLiteral("name"), folder.name},
            {QStringLiteral("isDefault"), folder.id == defaultFavoriteFolderId()}};
}

int FolderListModel::indexOfId(const QString &id) const {
    for (int i = 0; i < m_folders.size(); ++i) {
        if (m_folders[i].id == id)
            return i;
    }
    return 0;
}
