#include "app/PostListModel.h"

#include "core/FavoriteStore.h"
#include "core/SelectionStore.h"
#include "core/ServerStore.h"

PostListModel::PostListModel(QObject *parent)
    : QAbstractListModel(parent) {
}

int PostListModel::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_posts.size();
}

QVariant PostListModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= m_posts.size())
        return {};
    const BooruPost &post = m_posts[index.row()];
    switch (role) {
    case ServerIdRole:
        return post.serverId;
    case PostIdRole:
        return post.id;
    case GlobalIdRole:
        return post.globalId();
    case PreviewRole:
        return post.previewUrl.toString();
    case SampleRole:
        return post.viewerUrl().toString();
    case FileRole:
        return post.fileUrl.toString();
    case SourceRole:
        return post.sourceUrl.toString();
    case WidthRole:
        return post.width;
    case HeightRole:
        return post.height;
    case ScoreRole:
        return post.score;
    case TagsRole:
        return post.tags;
    case FileExtRole:
        return post.fileExt;
    case DuplicateRole:
        return post.duplicateCount;
    case BorderRole:
        return ServerStore::instance().enabledServers().size() > 1
            ? ServerStore::instance().colorFor(post.serverId).name()
            : QString();
    case FavoritedRole:
        return FavoriteStore::instance().contains(post.globalId());
    case AspectRole:
        return post.aspectRatio();
    case SelectedRole:
        return SelectionStore::instance().contains(post.globalId());
    default:
        return {};
    }
}

QHash<int, QByteArray> PostListModel::roleNames() const {
    return {
        {ServerIdRole, "serverId"},
        {PostIdRole, "postId"},
        {GlobalIdRole, "globalId"},
        {PreviewRole, "previewUrl"},
        {SampleRole, "sampleUrl"},
        {FileRole, "fileUrl"},
        {SourceRole, "sourceUrl"},
        {WidthRole, "imageWidth"},
        {HeightRole, "imageHeight"},
        {ScoreRole, "score"},
        {TagsRole, "tags"},
        {FileExtRole, "fileExt"},
        {DuplicateRole, "duplicateCount"},
        {BorderRole, "borderColor"},
        {FavoritedRole, "favorited"},
        {AspectRole, "aspectRatio"},
        {SelectedRole, "selected"},
    };
}

void PostListModel::setPosts(const QVector<BooruPost> &posts) {
    beginResetModel();
    m_posts = posts;
    endResetModel();
    emit countChanged();
}

void PostListModel::appendPosts(const QVector<BooruPost> &posts) {
    if (posts.isEmpty())
        return;
    const int start = m_posts.size();
    beginInsertRows({}, start, start + posts.size() - 1);
    m_posts += posts;
    endInsertRows();
    emit countChanged();
}

void PostListModel::clear() {
    beginResetModel();
    m_posts.clear();
    endResetModel();
    emit countChanged();
}

BooruPost PostListModel::at(int index) const {
    if (index < 0 || index >= m_posts.size())
        return {};
    return m_posts[index];
}

void PostListModel::refreshFavorites() {
    if (!m_posts.isEmpty())
        emit dataChanged(this->index(0), this->index(m_posts.size() - 1), {FavoritedRole});
}

void PostListModel::refreshSelection() {
    if (!m_posts.isEmpty())
        emit dataChanged(this->index(0), this->index(m_posts.size() - 1), {SelectedRole});
}
