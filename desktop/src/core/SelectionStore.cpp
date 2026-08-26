#include "core/SelectionStore.h"

SelectionStore &SelectionStore::instance() {
    static SelectionStore store;
    return store;
}

SelectionStore::SelectionStore(QObject *parent)
    : QAbstractListModel(parent) {
}

int SelectionStore::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_posts.size();
}

QVariant SelectionStore::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_posts.size())
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
    default:
        return {};
    }
}

QHash<int, QByteArray> SelectionStore::roleNames() const {
    return {{ServerIdRole, "serverId"}, {PostIdRole, "postId"}, {GlobalIdRole, "globalId"},
            {PreviewRole, "previewUrl"}, {SampleRole, "sampleUrl"}, {FileRole, "fileUrl"}};
}

bool SelectionStore::contains(const QString &globalId) const {
    return m_ids.contains(globalId);
}

void SelectionStore::toggle(const BooruPost &post) {
    const QString id = post.globalId();
    if (m_ids.contains(id)) {
        for (int i = 0; i < m_posts.size(); ++i) {
            if (m_posts[i].globalId() != id)
                continue;
            beginRemoveRows({}, i, i);
            m_ids.remove(id);
            m_posts.removeAt(i);
            endRemoveRows();
            emit countChanged();
            return;
        }
        return;
    }
    beginInsertRows({}, m_posts.size(), m_posts.size());
    m_ids.insert(id);
    m_posts.append(post);
    endInsertRows();
    emit countChanged();
}

void SelectionStore::removeAt(int index) {
    if (index < 0 || index >= m_posts.size())
        return;
    beginRemoveRows({}, index, index);
    m_ids.remove(m_posts[index].globalId());
    m_posts.removeAt(index);
    endRemoveRows();
    emit countChanged();
}

void SelectionStore::clear() {
    if (m_posts.isEmpty())
        return;
    beginResetModel();
    m_posts.clear();
    m_ids.clear();
    endResetModel();
    emit countChanged();
}

QVector<BooruPost> SelectionStore::takeAll() {
    const QVector<BooruPost> copy = m_posts;
    clear();
    return copy;
}
