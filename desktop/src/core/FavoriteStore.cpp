#include "core/FavoriteStore.h"

#include <algorithm>

#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSettings>

static BooruPost fromJson(const QJsonObject &object) {
    BooruPost post;
    post.serverId = object.value(QStringLiteral("serverId")).toString();
    post.id = object.value(QStringLiteral("id")).toInt();
    post.md5 = object.value(QStringLiteral("md5")).toString();
    post.tags = object.value(QStringLiteral("tags")).toString().split(QLatin1Char(' '), Qt::SkipEmptyParts);
    post.rating = Rating(object.value(QStringLiteral("rating")).toInt());
    post.score = object.value(QStringLiteral("score")).toInt();
    post.width = object.value(QStringLiteral("width")).toInt();
    post.height = object.value(QStringLiteral("height")).toInt();
    post.previewUrl = QUrl(object.value(QStringLiteral("previewUrl")).toString());
    post.sampleUrl = QUrl(object.value(QStringLiteral("sampleUrl")).toString());
    post.fileUrl = QUrl(object.value(QStringLiteral("fileUrl")).toString());
    post.fileExt = object.value(QStringLiteral("fileExt")).toString();
    post.sourceUrl = QUrl(object.value(QStringLiteral("sourceUrl")).toString());
    post.createdAt = qint64(object.value(QStringLiteral("createdAt")).toDouble());
    post.folderId = object.value(QStringLiteral("folderId")).toString();
    if (post.folderId.isEmpty())
        post.folderId = defaultFavoriteFolderId();
    return post;
}

static QJsonObject toJson(const BooruPost &post) {
    QJsonObject object;
    object.insert(QStringLiteral("serverId"), post.serverId);
    object.insert(QStringLiteral("id"), post.id);
    object.insert(QStringLiteral("md5"), post.md5);
    object.insert(QStringLiteral("tags"), post.tags.join(QLatin1Char(' ')));
    object.insert(QStringLiteral("rating"), int(post.rating));
    object.insert(QStringLiteral("score"), post.score);
    object.insert(QStringLiteral("width"), post.width);
    object.insert(QStringLiteral("height"), post.height);
    object.insert(QStringLiteral("previewUrl"), post.previewUrl.toString());
    object.insert(QStringLiteral("sampleUrl"), post.sampleUrl.toString());
    object.insert(QStringLiteral("fileUrl"), post.fileUrl.toString());
    object.insert(QStringLiteral("fileExt"), post.fileExt);
    object.insert(QStringLiteral("sourceUrl"), post.sourceUrl.toString());
    object.insert(QStringLiteral("createdAt"), double(post.createdAt));
    object.insert(QStringLiteral("folderId"), post.folderId);
    return object;
}

FavoriteStore &FavoriteStore::instance() {
    static FavoriteStore store;
    return store;
}

FavoriteStore::FavoriteStore(QObject *parent)
    : QObject(parent) {
    load();
}

void FavoriteStore::ensureDefaultFolder() {
    for (const FavoriteFolder &folder : m_folders) {
        if (folder.id == defaultFavoriteFolderId())
            return;
    }
    m_folders.prepend({defaultFavoriteFolderId(), QStringLiteral("Favorites")});
}

bool FavoriteStore::contains(const QString &globalId) const {
    return m_ids.contains(globalId);
}

void FavoriteStore::unfavorite(const QString &globalId) {
    if (!m_ids.contains(globalId))
        return;
    m_ids.remove(globalId);
    m_posts.erase(std::remove_if(m_posts.begin(), m_posts.end(),
                                 [&](const BooruPost &item) { return item.globalId() == globalId; }),
                  m_posts.end());
    save();
    emit changed();
}

static QString resolvedFolderId(const QVector<FavoriteFolder> &folders, const QString &folderId) {
    QString target = folderId.isEmpty() ? defaultFavoriteFolderId() : folderId;
    for (const FavoriteFolder &folder : folders) {
        if (folder.id == target)
            return target;
    }
    return defaultFavoriteFolderId();
}

void FavoriteStore::addToFolder(const BooruPost &post, const QString &folderId) {
    const QString target = resolvedFolderId(m_folders, folderId);
    const QString id = post.globalId();
    if (m_ids.contains(id)) {
        for (BooruPost &item : m_posts) {
            if (item.globalId() == id) {
                item.folderId = target;
                break;
            }
        }
    } else {
        BooruPost copy = post;
        copy.folderId = target;
        m_ids.insert(id);
        m_posts.prepend(copy);
    }
    m_lastFolderId = target;
    save();
    emit changed();
}

void FavoriteStore::addMany(const QVector<BooruPost> &posts, const QString &folderId) {
    if (posts.isEmpty())
        return;
    const QString target = resolvedFolderId(m_folders, folderId);
    for (const BooruPost &post : posts) {
        const QString id = post.globalId();
        if (m_ids.contains(id)) {
            for (BooruPost &item : m_posts) {
                if (item.globalId() == id)
                    item.folderId = target;
            }
        } else {
            BooruPost copy = post;
            copy.folderId = target;
            m_ids.insert(id);
            m_posts.prepend(copy);
        }
    }
    m_lastFolderId = target;
    save();
    emit changed();
}

void FavoriteStore::updateSnapshot(const BooruPost &post) {
    for (BooruPost &item : m_posts) {
        if (item.globalId() != post.globalId())
            continue;
        const QString folder = item.folderId;
        item = post;
        item.folderId = folder;
        save();
        emit changed();
        return;
    }
}

QVector<BooruPost> FavoriteStore::posts() const {
    return m_posts;
}

QVector<BooruPost> FavoriteStore::postsInFolder(const QString &folderId) const {
    QVector<BooruPost> result;
    for (const BooruPost &post : m_posts) {
        if (post.folderId == folderId)
            result.append(post);
    }
    return result;
}

QString FavoriteStore::createFolder(const QString &name) {
    const QString cleaned = name.trimmed();
    if (cleaned.isEmpty())
        return m_lastFolderId;
    FavoriteFolder folder;
    folder.id = QUuid::createUuid().toString(QUuid::WithoutBraces);
    folder.name = cleaned;
    m_folders.append(folder);
    m_lastFolderId = folder.id;
    save();
    emit changed();
    return folder.id;
}

void FavoriteStore::renameFolder(const QString &id, const QString &name) {
    const QString cleaned = name.trimmed();
    if (cleaned.isEmpty() || id == defaultFavoriteFolderId())
        return;
    for (FavoriteFolder &folder : m_folders) {
        if (folder.id != id)
            continue;
        folder.name = cleaned;
        save();
        emit changed();
        return;
    }
}

void FavoriteStore::deleteFolder(const QString &id, bool deletePosts) {
    if (id == defaultFavoriteFolderId())
        return;
    if (deletePosts) {
        m_posts.erase(std::remove_if(m_posts.begin(), m_posts.end(),
                                     [&](const BooruPost &post) {
                                         if (post.folderId != id)
                                             return false;
                                         m_ids.remove(post.globalId());
                                         return true;
                                     }),
                      m_posts.end());
    } else {
        for (BooruPost &post : m_posts) {
            if (post.folderId == id)
                post.folderId = defaultFavoriteFolderId();
        }
    }
    m_folders.erase(std::remove_if(m_folders.begin(), m_folders.end(),
                                   [&](const FavoriteFolder &folder) { return folder.id == id; }),
                    m_folders.end());
    if (m_lastFolderId == id)
        m_lastFolderId = defaultFavoriteFolderId();
    save();
    emit changed();
}

FavoriteFolder FavoriteStore::folder(const QString &id) const {
    for (const FavoriteFolder &folder : m_folders) {
        if (folder.id == id)
            return folder;
    }
    return {};
}

void FavoriteStore::load() {
    QSettings settings;
    const QByteArray folderRaw = settings.value(QStringLiteral("favorites/folders")).toByteArray();
    const QJsonArray folderArray = QJsonDocument::fromJson(folderRaw).array();
    for (const QJsonValue &value : folderArray) {
        const QJsonObject object = value.toObject();
        FavoriteFolder folder;
        folder.id = object.value(QStringLiteral("id")).toString();
        folder.name = object.value(QStringLiteral("name")).toString();
        if (!folder.id.isEmpty())
            m_folders.append(folder);
    }
    ensureDefaultFolder();
    m_lastFolderId = settings.value(QStringLiteral("favorites/lastFolder"), defaultFavoriteFolderId()).toString();

    const QByteArray raw = settings.value(QStringLiteral("favorites/json")).toByteArray();
    const QJsonArray array = QJsonDocument::fromJson(raw).array();
    for (const QJsonValue &value : array) {
        BooruPost post = fromJson(value.toObject());
        if (post.id <= 0 || post.serverId.isEmpty())
            continue;
        if (m_ids.contains(post.globalId()))
            continue;
        bool knownFolder = false;
        for (const FavoriteFolder &folder : m_folders) {
            if (folder.id == post.folderId)
                knownFolder = true;
        }
        if (!knownFolder)
            post.folderId = defaultFavoriteFolderId();
        m_ids.insert(post.globalId());
        m_posts.append(post);
    }
    bool lastKnown = false;
    for (const FavoriteFolder &folder : m_folders) {
        if (folder.id == m_lastFolderId)
            lastKnown = true;
    }
    if (!lastKnown)
        m_lastFolderId = defaultFavoriteFolderId();
}

void FavoriteStore::save() const {
    QJsonArray posts;
    for (const BooruPost &post : m_posts)
        posts.append(toJson(post));
    QJsonArray folders;
    for (const FavoriteFolder &folder : m_folders) {
        QJsonObject object;
        object.insert(QStringLiteral("id"), folder.id);
        object.insert(QStringLiteral("name"), folder.name);
        folders.append(object);
    }
    QSettings settings;
    settings.setValue(QStringLiteral("favorites/json"), QJsonDocument(posts).toJson(QJsonDocument::Compact));
    settings.setValue(QStringLiteral("favorites/folders"), QJsonDocument(folders).toJson(QJsonDocument::Compact));
    settings.setValue(QStringLiteral("favorites/lastFolder"), m_lastFolderId);
}
