#ifndef POST_H
#define POST_H

#include <QString>
#include <QDateTime>
#include <QUrl>
#include <QList>
#include <QVariantMap>

class Post {
public:
    Post();
    Post(const QString& id, const QString& title, const QString& content,
         const QString& published, const QString& edited, const QString& author,
         const QString& service, const QString& url, const QString& thumbnail = "");

    QString id() const { return m_id; }
    void setId(const QString& id) { m_id = id; }

    QString title() const { return m_title; }
    void setTitle(const QString& title) { m_title = title; }

    QString content() const { return m_content; }
    void setContent(const QString& content) { m_content = content; }

    QString published() const { return m_published; }
    void setPublished(const QString& published) { m_published = published; }

    QString edited() const { return m_edited; }
    void setEdited(const QString& edited) { m_edited = edited; }

    QString author() const { return m_author; }
    void setAuthor(const QString& author) { m_author = author; }

    QString service() const { return m_service; }
    void setService(const QString& service) { m_service = service; }

    QString url() const { return m_url; }
    void setUrl(const QString& url) { m_url = url; }

    QString thumbnail() const { return m_thumbnail; }
    void setThumbnail(const QString& thumbnail) { m_thumbnail = thumbnail; }

    QList<QVariantMap> attachments() const { return m_attachments; }
    void setAttachments(const QList<QVariantMap>& attachments) { m_attachments = attachments; }

    QList<QVariantMap> embeds() const { return m_embeds; }
    void setEmbeds(const QList<QVariantMap>& embeds) { m_embeds = embeds; }

    QList<QVariantMap> files() const { return m_files; }
    void setFiles(const QList<QVariantMap>& files) { m_files = files; }

private:
    QString m_id;
    QString m_title;
    QString m_content;
    QString m_published;
    QString m_edited;
    QString m_author;
    QString m_service;
    QString m_url;
    QString m_thumbnail;
    QList<QVariantMap> m_attachments;
    QList<QVariantMap> m_embeds;
    QList<QVariantMap> m_files;
};

#endif // POST_H


