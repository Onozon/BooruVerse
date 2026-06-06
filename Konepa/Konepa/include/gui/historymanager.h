#ifndef HISTORYMANAGER_H
#define HISTORYMANAGER_H

#include "models/artist.h"
#include "models/post.h"
#include <QList>
#include <QString>
#include <QDateTime>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonDocument>
#include "core/lockmanager.h"

class HistoryManager
{
public:
    struct HistoryEntry {
        QString type; // "artist" or "post"
        Artist artist;
        Post post;
        QDateTime timestamp;
        
        QJsonObject toJson() const;
        static HistoryEntry fromJson(const QJsonObject& obj);
    };
    
    HistoryManager();
    ~HistoryManager();
    
    void addArtist(const Artist& artist);
    void addPost(const Post& post);
    
    QList<Artist> getRecentArtists(int limit = 50) const;
    QList<Post> getRecentPosts(int limit = 50) const;
    
    void save();
    void load();
    
private:
    QList<HistoryEntry> m_history;
    QString m_historyFile;
    
    void removeDuplicates(const QString& id, const QString& type);
};

#endif // HISTORYMANAGER_H




