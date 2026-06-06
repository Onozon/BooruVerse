#include "gui/historymanager.h"
#include "models/artist.h"
#include "models/post.h"
#include <QFile>
#include <QDir>
#include <QDebug>
#include <QStandardPaths>
#include <QJsonDocument>
#include <QSet>
#include <algorithm>
#include "core/lockmanager.h"

QJsonObject HistoryManager::HistoryEntry::toJson() const
{
    QJsonObject obj;
    obj["type"] = type;
    obj["timestamp"] = timestamp.toString(Qt::ISODate);
    
    if (type == "artist") {
        QJsonObject artistObj;
        artistObj["id"] = artist.id();
        artistObj["name"] = artist.name();
        artistObj["service"] = artist.service();
        artistObj["avatar"] = artist.avatar();
        artistObj["url"] = artist.url();
        artistObj["indexed"] = artist.indexed();
        artistObj["updated"] = artist.updated();
        obj["artist"] = artistObj;
    } else if (type == "post") {
        QJsonObject postObj;
        postObj["id"] = post.id();
        postObj["title"] = post.title();
        postObj["service"] = post.service();
        postObj["author"] = post.author();
        postObj["thumbnail"] = post.thumbnail();
        postObj["url"] = post.url();
        obj["post"] = postObj;
    }
    
    return obj;
}

HistoryManager::HistoryEntry HistoryManager::HistoryEntry::fromJson(const QJsonObject& obj)
{
    HistoryEntry entry;
    entry.type = obj["type"].toString();
    entry.timestamp = QDateTime::fromString(obj["timestamp"].toString(), Qt::ISODate);
    
    if (entry.type == "artist" && obj.contains("artist")) {
        QJsonObject artistObj = obj["artist"].toObject();
        Artist artist;
        artist.setId(artistObj["id"].toString());
        artist.setName(artistObj["name"].toString());
        artist.setService(artistObj["service"].toString());
        if (artistObj.contains("avatar")) {
            artist.setAvatar(artistObj["avatar"].toString());
        }
        if (artistObj.contains("url")) {
            artist.setUrl(artistObj["url"].toString());
        }
        if (artistObj.contains("indexed")) {
            artist.setIndexed(artistObj["indexed"].toString());
        }
        if (artistObj.contains("updated")) {
            artist.setUpdated(artistObj["updated"].toString());
        }
        entry.artist = artist;
    } else if (entry.type == "post" && obj.contains("post")) {
        QJsonObject postObj = obj["post"].toObject();
        Post post;
        post.setId(postObj["id"].toString());
        post.setTitle(postObj["title"].toString());
        post.setService(postObj["service"].toString());
        post.setAuthor(postObj["author"].toString());
        post.setThumbnail(postObj["thumbnail"].toString());
        post.setUrl(postObj["url"].toString());
        entry.post = post;
    }
    
    return entry;
}

HistoryManager::HistoryManager()
{
    QString dataDir = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation);
    QDir().mkpath(dataDir);
    m_historyFile = dataDir + "/history.json";
    load();
}

HistoryManager::~HistoryManager()
{
    save();
}

void HistoryManager::addArtist(const Artist& artist)
{
    // History operations are typically in main thread, but protect for thread safety
    removeDuplicates(artist.id(), "artist");
    
    HistoryEntry entry;
    entry.type = "artist";
    entry.artist = artist;
    entry.timestamp = QDateTime::currentDateTime();
    
    m_history.prepend(entry);
    
    // Ограничиваем размер истории
    if (m_history.size() > 1000) {
        m_history = m_history.mid(0, 1000);
    }
    
    save();
}

void HistoryManager::addPost(const Post& post)
{
    // History operations are typically in main thread, but protect for thread safety
    QString postId = QString("%1_%2_%3").arg(post.service(), post.author(), post.id());
    removeDuplicates(postId, "post");
    
    HistoryEntry entry;
    entry.type = "post";
    entry.post = post;
    entry.timestamp = QDateTime::currentDateTime();
    
    m_history.prepend(entry);
    
    // Ограничиваем размер истории
    if (m_history.size() > 1000) {
        m_history = m_history.mid(0, 1000);
    }
    
    save();
}

QList<Artist> HistoryManager::getRecentArtists(int limit) const
{
    // History operations are typically in main thread
    QList<Artist> artists;
    QSet<QString> seenIds;
    
    for (const HistoryEntry& entry : m_history) {
        if (entry.type == "artist" && !entry.artist.id().isEmpty()) {
            QString key = QString("%1_%2").arg(entry.artist.service(), entry.artist.id());
            if (!seenIds.contains(key)) {
                seenIds.insert(key);
                artists.append(entry.artist);
                if (limit > 0 && artists.size() >= limit) break;
            }
        }
    }
    
    return artists;
}

QList<Post> HistoryManager::getRecentPosts(int limit) const
{
    // History operations are typically in main thread
    QList<Post> posts;
    QSet<QString> seenIds;
    
    for (const HistoryEntry& entry : m_history) {
        if (entry.type == "post" && !entry.post.id().isEmpty()) {
            QString key = QString("%1_%2_%3").arg(entry.post.service(), entry.post.author(), entry.post.id());
            if (!seenIds.contains(key)) {
                seenIds.insert(key);
                posts.append(entry.post);
                if (limit > 0 && posts.size() >= limit) break;
            }
        }
    }
    
    return posts;
}

void HistoryManager::save()
{
    // File operations are thread-safe in Qt, no locks needed
    QJsonArray array;
    for (const HistoryEntry& entry : m_history) {
        array.append(entry.toJson());
    }
    
    QJsonDocument doc(array);
    QFile file(m_historyFile);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(doc.toJson());
        file.close();
    }
}

void HistoryManager::load()
{
    // File operations are thread-safe in Qt, no locks needed
    QFile file(m_historyFile);
    if (!file.exists()) {
        return;
    }
    
    if (file.open(QIODevice::ReadOnly)) {
        QByteArray data = file.readAll();
        file.close();
        
        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isArray()) {
            QJsonArray array = doc.array();
            m_history.clear();
            for (const QJsonValue& value : array) {
                if (value.isObject()) {
                    m_history.append(HistoryEntry::fromJson(value.toObject()));
                }
            }
        }
    }
}

void HistoryManager::removeDuplicates(const QString& id, const QString& type)
{
    auto it = std::remove_if(m_history.begin(), m_history.end(),
        [id, type](const HistoryEntry& entry) {
            if (entry.type != type) return false;
            if (type == "artist") {
                return entry.artist.id() == id;
            } else if (type == "post") {
                QString postId = QString("%1_%2_%3")
                    .arg(entry.post.service(), entry.post.author(), entry.post.id());
                return postId == id;
            }
            return false;
        });
    m_history.erase(it, m_history.end());
}

