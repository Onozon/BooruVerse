#include "models/artist.h"

Artist::Artist()
    : m_id(""), m_service(""), m_name(""), m_indexed(""), m_updated(""), m_url(""), m_avatar("")
{
}

Artist::Artist(const QString& id, const QString& service, const QString& name,
               const QString& indexed, const QString& updated, const QString& url,
               const QString& avatar)
    : m_id(id), m_service(service), m_name(name), m_indexed(indexed), m_updated(updated),
      m_url(url), m_avatar(avatar)
{
    ensureUrl();
}

void Artist::ensureUrl()
{
    if (m_url.isEmpty() && !m_service.isEmpty() && !m_id.isEmpty()) {
        m_url = QString("https://kemono.cr/%1/user/%2").arg(m_service, m_id);
    }
    if (m_avatar.isEmpty() && !m_service.isEmpty() && !m_id.isEmpty()) {
        m_avatar = QString("https://img.kemono.cr/icons/%1/%2").arg(m_service, m_id);
    }
}


