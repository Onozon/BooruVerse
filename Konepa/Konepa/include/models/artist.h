#ifndef ARTIST_H
#define ARTIST_H

#include <QString>
#include <QDateTime>
#include <QUrl>

class Artist {
public:
    Artist();
    Artist(const QString& id, const QString& service, const QString& name,
           const QString& indexed, const QString& updated, const QString& url = "",
           const QString& avatar = "");

    QString id() const { return m_id; }
    void setId(const QString& id) { m_id = id; }

    QString service() const { return m_service; }
    void setService(const QString& service) { m_service = service; }

    QString name() const { return m_name; }
    void setName(const QString& name) { m_name = name; }

    QString indexed() const { return m_indexed; }
    void setIndexed(const QString& indexed) { m_indexed = indexed; }

    QString updated() const { return m_updated; }
    void setUpdated(const QString& updated) { m_updated = updated; }

    QString url() const { return m_url; }
    void setUrl(const QString& url) { m_url = url; }

    QString avatar() const { return m_avatar; }
    void setAvatar(const QString& avatar) { m_avatar = avatar; }

    // Формирует URL если не указан
    void ensureUrl();

private:
    QString m_id;
    QString m_service;
    QString m_name;
    QString m_indexed;
    QString m_updated;
    QString m_url;
    QString m_avatar;
};

#endif // ARTIST_H


