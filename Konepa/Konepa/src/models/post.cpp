#include "models/post.h"

Post::Post()
    : m_id(""), m_title(""), m_content(""), m_published(""), m_edited(""),
      m_author(""), m_service(""), m_url(""), m_thumbnail("")
{
}

Post::Post(const QString& id, const QString& title, const QString& content,
           const QString& published, const QString& edited, const QString& author,
           const QString& service, const QString& url, const QString& thumbnail)
    : m_id(id), m_title(title), m_content(content), m_published(published),
      m_edited(edited), m_author(author), m_service(service), m_url(url),
      m_thumbnail(thumbnail)
{
}


