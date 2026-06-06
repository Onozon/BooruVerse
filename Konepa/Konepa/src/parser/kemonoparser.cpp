#include "parser/kemonoparser.h"
#include <QJsonDocument>
#include <QJsonObject>
#include <QJsonArray>
#include <QUrlQuery>
#include <QDebug>
#include <QFile>
#include <QIODevice>
#include <zlib.h>
#include "core/lockmanager.h"
#include "core/threadpool.h"

KemonoParser::KemonoParser(QObject *parent)
    : QObject(parent), m_baseUrl("https://kemono.cr")
{
    setupNetworkManager();
}

KemonoParser::KemonoParser(const QString& baseUrl, QObject *parent)
    : QObject(parent), m_baseUrl(baseUrl)
{
    setupNetworkManager();
}

KemonoParser::~KemonoParser()
{
    if (m_networkManager) {
        delete m_networkManager;
    }
}

void KemonoParser::setupNetworkManager()
{
    if (m_networkManager) {
        qDebug() << "Network manager already exists";
        return;
    }
    
    m_networkManager = new QNetworkAccessManager(this);
    if (!m_networkManager) {
        qDebug() << "ERROR: Failed to create network manager!";
        return;
    }
    
    connect(m_networkManager, &QNetworkAccessManager::finished,
            this, [this](QNetworkReply* reply) {
                this->onNetworkReplyFinished(reply);
            });
    qDebug() << "Network manager created and connected";
}

QNetworkRequest KemonoParser::createRequest(const QString& url)
{
    // Убираем кавычки если они есть
    QString cleanUrl = url;
    cleanUrl.remove('"');
    cleanUrl = cleanUrl.trimmed();
    
    QUrl qurl(cleanUrl);
    if (!qurl.isValid()) {
        qDebug() << "ERROR: Invalid URL:" << cleanUrl;
        return QNetworkRequest();
    }
    
    qDebug() << "Creating request for URL:" << qurl.toString();
    QNetworkRequest request(qurl);
    
    // Для API запросов используем 'text/css' как в Python версии
    bool isApiRequest = qurl.path().contains("/api/v1/");
    
    // Полные заголовки как в Python версии для обхода защиты
    request.setRawHeader("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
    
    if (isApiRequest) {
        // Для API используем 'text/css' как в Python версии
        request.setRawHeader("Accept", "text/css");
    } else {
        request.setRawHeader("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8");
    }
    
    request.setRawHeader("Accept-Language", "en-US,en;q=0.5");
    request.setRawHeader("Accept-Encoding", "gzip, deflate, br");
    request.setRawHeader("Connection", "keep-alive");
    request.setRawHeader("Upgrade-Insecure-Requests", "1");
    request.setRawHeader("DNT", "1");
    request.setRawHeader("Sec-Fetch-Dest", "document");
    request.setRawHeader("Sec-Fetch-Mode", "navigate");
    request.setRawHeader("Sec-Fetch-Site", "none");
    request.setRawHeader("Sec-Fetch-User", "?1");
    request.setRawHeader("Cache-Control", "max-age=0");
    request.setRawHeader("sec-ch-ua", "\"Not_A Brand\";v=\"8\", \"Chromium\";v=\"120\", \"Google Chrome\";v=\"120\"");
    request.setRawHeader("sec-ch-ua-mobile", "?0");
    request.setRawHeader("sec-ch-ua-platform", "\"macOS\"");
    
    // Referer - важно для обхода защиты
    request.setRawHeader("Referer", "https://kemono.cr/");
    
    // Загружаем сессионную куку если есть
    QString cookieFile = "session_cookie.txt";
    QFile file(cookieFile);
    if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QString sessionCookie = QString::fromUtf8(file.readAll()).trimmed();
        if (!sessionCookie.isEmpty()) {
            request.setRawHeader("Cookie", QString("session=%1").arg(sessionCookie).toUtf8());
            qDebug() << "Using session cookie from file";
        }
        file.close();
    }
    
    return request;
}

void KemonoParser::searchArtists(const QString& query, int limit, int offset)
{
    // Кодируем query для URL
    QString encodedQuery = QUrl::toPercentEncoding(query);
    QString url = QString("%1/api/v1/creators?q=%2&limit=%3&offset=%4")
                  .arg(m_baseUrl, encodedQuery, QString::number(limit), QString::number(offset));
    
    qDebug() << "Searching artists, URL:" << url;
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !request.url().isValid()) {
        qDebug() << "ERROR: Failed to create request, URL:" << url;
        emit error("Invalid URL");
        return;
    }
    
    if (!m_networkManager) {
        qDebug() << "ERROR: Network manager is null!";
        emit error("Network manager not initialized");
        return;
    }
    
    qDebug() << "Calling networkManager->get()...";
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (!reply) {
            qDebug() << "ERROR: Failed to create network reply! Network manager state:" << m_networkManager;
            emit error("Failed to create network request");
            return;
        }
        
        m_replyTypes[reply] = "searchArtists";
        m_replyLimits[reply] = limit;
        m_replyOffsets[reply] = offset;
    }
    qDebug() << "Network request created successfully, reply:" << reply << "type:" << m_replyTypes[reply] << "limit:" << limit << "offset:" << offset;
}

void KemonoParser::getRecentArtists(int limit, int offset)
{
    QString url = QString("%1/api/v1/creators?limit=%2&offset=%3")
                  .arg(m_baseUrl, QString::number(limit), QString::number(offset));
    
    qDebug() << "Getting recent artists, URL:" << url;
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty()) {
        qDebug() << "ERROR: Failed to create request";
        emit error("Invalid URL");
        return;
    }
    
    if (!m_networkManager) {
        qDebug() << "ERROR: Network manager is null!";
        emit error("Network manager not initialized");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (!reply) {
            qDebug() << "ERROR: Failed to create network reply!";
            emit error("Failed to create network request");
            return;
        }
        
        m_replyTypes[reply] = "recentArtists";
        m_replyLimits[reply] = limit;
        m_replyOffsets[reply] = offset;
    }
    qDebug() << "Network request created, reply:" << reply << "limit:" << limit << "offset:" << offset;
}

void KemonoParser::getAllArtists()
{
    // Загружаем всех пользователей без лимита
    QString url = QString("%1/api/v1/creators").arg(m_baseUrl);
    
    qDebug() << "Getting all artists, URL:" << url;
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        qDebug() << "ERROR: Failed to create request";
        emit error("Invalid URL");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (!reply) {
            qDebug() << "ERROR: Failed to create network reply!";
            emit error("Failed to create network request");
            return;
        }
        
        m_replyTypes[reply] = "allArtists";
        m_replyLimits[reply] = 0; // 0 означает "все"
        m_replyOffsets[reply] = 0;
    }
    qDebug() << "Network request created for all artists";
}

void KemonoParser::getArtistsPage(int limit, int offset)
{
    QString url = QString("%1/api/v1/creators?limit=%2&offset=%3")
                  .arg(m_baseUrl, QString::number(limit), QString::number(offset));
    
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "artistsPage";
            m_replyLimits[reply] = limit;
            m_replyOffsets[reply] = offset;
        }
    }
}

void KemonoParser::getArtistPosts(const Artist& artist, int limit, int offset)
{
    // Пробуем несколько вариантов API endpoint:
    // 1. /api/v1/{service}/user/{id} - может не работать
    // 2. /api/v1/{service}/user/{id}/posts - альтернативный формат
    // 3. Используем HTML URL как fallback (как в Python версии)
    
    // Сначала пробуем API endpoint без параметров
    QString url = QString("%1/api/v1/%2/user/%3")
                  .arg(m_baseUrl, artist.service(), artist.id());
    
    qDebug() << "Getting artist posts for:" << artist.name() << "service:" << artist.service() << "id:" << artist.id();
    qDebug() << "Trying API URL:" << url;
    
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        qDebug() << "ERROR: Invalid request or network manager";
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "artistPosts";
            m_replyLimits[reply] = limit;
            m_replyOffsets[reply] = offset;
            // Сохраняем информацию об артисте для fallback
            m_replyArtists[reply] = artist;
            qDebug() << "Network request created for artist posts";
        } else {
            qDebug() << "ERROR: Failed to create network reply";
            emit error("Failed to create network request");
        }
    }
}

void KemonoParser::getAllArtistPosts(const Artist& artist)
{
    // Загружаем все посты пользователя (используем /posts endpoint)
    QString url = QString("%1/api/v1/%2/user/%3/posts")
                  .arg(m_baseUrl, artist.service(), artist.id());
    
    qDebug() << "Getting all posts for artist:" << artist.name() << "service:" << artist.service() << "id:" << artist.id();
    qDebug() << "URL:" << url;
    
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        qDebug() << "ERROR: Invalid request or network manager";
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "allArtistPosts";
            m_replyLimits[reply] = 0; // 0 означает "все"
            m_replyOffsets[reply] = 0;
            m_replyArtists[reply] = artist;
            qDebug() << "Network request created for all artist posts";
        } else {
            qDebug() << "ERROR: Failed to create network reply";
            emit error("Failed to create network request");
        }
    }
}

void KemonoParser::getPost(const QString& service, const QString& userId, const QString& postId)
{
    QString url = QString("%1/api/v1/%2/user/%3/post/%4")
                  .arg(m_baseUrl, service, userId, postId);
    
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "post";
        }
    }
}

void KemonoParser::getArtistInfo(const QString& service, const QString& userId)
{
    QString url = QString("%1/api/v1/%2/user/%3")
                  .arg(m_baseUrl, service, userId);
    
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "artistInfo";
        }
    }
}

void KemonoParser::getPopularArtists(int limit)
{
    // API возвращает авторов отсортированных по faved (избранное)
    QString url = QString("%1/api/v1/creators?sort=faved").arg(m_baseUrl);
    
    qDebug() << "Getting popular artists, URL:" << url;
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "popularArtists";
            m_replyLimits[reply] = limit;
            m_replyOffsets[reply] = 0;
        }
    }
}

void KemonoParser::getRecentlyUpdatedArtists(int limit)
{
    // API возвращает авторов отсортированных по дате обновления
    QString url = QString("%1/api/v1/creators?sort=updated").arg(m_baseUrl);
    
    qDebug() << "Getting recently updated artists, URL:" << url;
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "recentlyUpdatedArtists";
            m_replyLimits[reply] = limit;
            m_replyOffsets[reply] = 0;
        }
    }
}

void KemonoParser::getRandomArtist()
{
    // Kemono API поддерживает получение случайного автора
    QString url = QString("%1/api/v1/creators/random").arg(m_baseUrl);
    
    qDebug() << "Getting random artist, URL:" << url;
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "randomArtist";
        }
    }
}

void KemonoParser::getRandomPost()
{
    // Kemono API поддерживает получение случайного поста
    QString url = QString("%1/api/v1/posts/random").arg(m_baseUrl);
    
    qDebug() << "Getting random post, URL:" << url;
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "randomPost";
        }
    }
}

void KemonoParser::searchPosts(const QString& query, const QString& sortBy, int offset)
{
    Q_UNUSED(sortBy);
    // Kemono API: /api/v1/posts/search?q=query
    QString url = QString("%1/api/v1/posts/search?q=%2&o=%3")
                  .arg(m_baseUrl, QUrl::toPercentEncoding(query), QString::number(offset));
    
    qDebug() << "Searching posts, URL:" << url;
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "searchPosts";
            m_replyOffsets[reply] = offset;
        }
    }
}

void KemonoParser::getPopularPosts(int offset)
{
    // Kemono API: /api/v1/favorites с сортировкой
    // Или используем /api/v1/recent который возвращает последние посты
    QString url = QString("%1/api/v1/recent?o=%2").arg(m_baseUrl, QString::number(offset));
    
    qDebug() << "Getting popular/recent posts, URL:" << url;
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "popularPosts";
            m_replyOffsets[reply] = offset;
        }
    }
}

void KemonoParser::getRecentPosts(int offset)
{
    // Kemono API: /api/v1/recent возвращает последние посты
    QString url = QString("%1/api/v1/recent?o=%2").arg(m_baseUrl, QString::number(offset));
    
    qDebug() << "Getting recent posts, URL:" << url;
    QNetworkRequest request = createRequest(url);
    if (request.url().isEmpty() || !m_networkManager) {
        emit error("Invalid request");
        return;
    }
    
    QNetworkReply* reply = nullptr;
    {
        LOCK_MUTEX(NetworkRequests);
        reply = m_networkManager->get(request);
        if (reply) {
            m_replyTypes[reply] = "recentPosts";
            m_replyOffsets[reply] = offset;
        }
    }
}

void KemonoParser::onNetworkReplyFinished(QNetworkReply* reply)
{
    if (!reply) {
        qDebug() << "ERROR: reply is null in onNetworkReplyFinished!";
        return;
    }

    // Get reply type and parameters first (with lock)
    QString replyType;
    int limit = 0;
    int offset = 0;
    Artist artist;
    {
        LOCK_MUTEX(NetworkRequests);
        replyType = m_replyTypes.value(reply);
        limit = m_replyLimits.value(reply, 0);
        offset = m_replyOffsets.value(reply, 0);
        artist = m_replyArtists.value(reply);
    }
    qDebug() << "Network reply finished, type:" << replyType << "limit:" << limit << "offset:" << offset;
    
    // Check for network errors (except for artistPosts, which we handle specially)
    if (reply->error() != QNetworkReply::NoError && replyType != "artistPosts") {
        qDebug() << "Network error:" << reply->errorString();
        emit error(QString("Network error: %1").arg(reply->errorString()));
        {
            LOCK_MUTEX(NetworkRequests);
            m_replyTypes.remove(reply);
            m_replyLimits.remove(reply);
            m_replyOffsets.remove(reply);
            m_replyArtists.remove(reply);
        }
        reply->deleteLater();
        return;
    }

    QByteArray data = reply->readAll();
    qDebug() << "Received data size:" << data.size() << "bytes";
    qDebug() << "Response headers:" << reply->rawHeaderPairs();
    
    // Check if data is gzip compressed (magic bytes: 0x1F 0x8B)
    if (data.size() >= 2 && static_cast<unsigned char>(data[0]) == 0x1F && 
        static_cast<unsigned char>(data[1]) == 0x8B) {
        qDebug() << "Data is gzip compressed, decompressing...";
        
        // Decompress gzip data
        z_stream zs;
        memset(&zs, 0, sizeof(zs));
        
        // Initialize zlib for gzip
        if (inflateInit2(&zs, 16 + MAX_WBITS) != Z_OK) {
            qDebug() << "Failed to initialize zlib for gzip decompression";
            emit error("Failed to decompress gzip data");
            {
                LOCK_MUTEX(NetworkRequests);
                m_replyTypes.remove(reply);
                m_replyLimits.remove(reply);
                m_replyOffsets.remove(reply);
                m_replyArtists.remove(reply);
            }
            reply->deleteLater();
            return;
        }
        
        // Create non-const copy for zlib (it doesn't modify input, but requires non-const pointer)
        QByteArray dataCopy = data;
        zs.next_in = reinterpret_cast<Bytef*>(dataCopy.data());
        zs.avail_in = dataCopy.size();
        
        QByteArray decompressed;
        char buffer[32768];
        int ret;
        
        do {
            zs.next_out = reinterpret_cast<Bytef*>(buffer);
            zs.avail_out = sizeof(buffer);
            
            ret = inflate(&zs, Z_NO_FLUSH);
            
            if (ret == Z_OK || ret == Z_STREAM_END) {
                decompressed.append(buffer, sizeof(buffer) - zs.avail_out);
            }
        } while (ret == Z_OK);
        
        inflateEnd(&zs);
        
        if (ret == Z_STREAM_END) {
            data = decompressed;
            qDebug() << "Decompressed data size:" << data.size() << "bytes";
        } else {
            qDebug() << "Gzip decompression failed, error:" << ret;
            emit error("Failed to decompress gzip data");
            {
                LOCK_MUTEX(NetworkRequests);
                m_replyTypes.remove(reply);
                m_replyLimits.remove(reply);
                m_replyOffsets.remove(reply);
                m_replyArtists.remove(reply);
            }
            reply->deleteLater();
            return;
        }
    }
    
    qDebug() << "First 500 bytes of response:" << data.left(500);

    if (replyType == "searchArtists" || replyType == "recentArtists" || replyType == "artistsPage" || replyType == "allArtists" 
        || replyType == "popularArtists" || replyType == "recentlyUpdatedArtists") {
        qDebug() << "Parsing artists from JSON... (limit:" << limit << "offset:" << offset << "type:" << replyType << ")";
        QList<Artist> artists;
        if (replyType == "allArtists" || replyType == "popularArtists" || replyType == "recentlyUpdatedArtists") {
            // Для всех/популярных/недавних применяем только лимит
            artists = parseArtistsFromJson(data, limit, 0);
        } else {
            artists = parseArtistsFromJson(data, limit, offset);
        }
        qDebug() << "Parsed" << artists.size() << "artists, emitting signal";
        
        // Выбираем правильный сигнал
        if (replyType == "allArtists") {
            emit allArtistsLoaded(artists);
        } else if (replyType == "popularArtists") {
            emit popularArtistsLoaded(artists);
        } else if (replyType == "recentlyUpdatedArtists") {
            emit recentlyUpdatedArtistsLoaded(artists);
        } else {
            emit artistsFound(artists);
        }
    } else if (replyType == "randomArtist") {
        // Случайный автор - API возвращает один объект или массив с одним элементом
        QJsonParseError parseError;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
        if (parseError.error == QJsonParseError::NoError) {
            Artist artist;
            if (doc.isObject()) {
                artist = parseArtistFromJson(doc.object());
            } else if (doc.isArray() && !doc.array().isEmpty()) {
                artist = parseArtistFromJson(doc.array().first().toObject());
            }
            if (!artist.id().isEmpty()) {
                emit randomArtistLoaded(artist);
            } else {
                emit error("Failed to parse random artist");
            }
        } else {
            emit error("Failed to parse random artist JSON");
        }
    } else if (replyType == "randomPost") {
        // Случайный пост
        QJsonParseError parseError;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
        if (parseError.error == QJsonParseError::NoError) {
            Post post;
            if (doc.isObject()) {
                QJsonObject obj = doc.object();
                if (obj.contains("post")) {
                    post = parsePostFromJson(obj["post"].toObject());
                } else {
                    post = parsePostFromJson(obj);
                }
            } else if (doc.isArray() && !doc.array().isEmpty()) {
                post = parsePostFromJson(doc.array().first().toObject());
            }
            if (!post.id().isEmpty()) {
                emit randomPostLoaded(post);
            } else {
                emit error("Failed to parse random post");
            }
        } else {
            emit error("Failed to parse random post JSON");
        }
    } else if (replyType == "searchPosts" || replyType == "popularPosts" || replyType == "recentPosts") {
        qDebug() << "Parsing posts from JSON... (type:" << replyType << ")";
        QList<Post> posts = parsePostsFromJson(data);
        qDebug() << "Parsed" << posts.size() << "posts, emitting signal";
        
        if (replyType == "searchPosts") {
            emit searchPostsFound(posts);
        } else if (replyType == "popularPosts") {
            emit popularPostsLoaded(posts);
        } else if (replyType == "recentPosts") {
            emit recentPostsLoaded(posts);
        }
    } else if (replyType == "artistPosts" || replyType == "allArtistPosts") {
        // Check if response contains an error message
        QJsonParseError parseError;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
        if (parseError.error == QJsonParseError::NoError && doc.isObject()) {
            QJsonObject obj = doc.object();
            if (obj.contains("error")) {
                QString errorMsg = obj.value("error").toString();
                qDebug() << "API returned error:" << errorMsg;
                
                // Try alternative URL format with /posts
                QString altUrl = QString("%1/api/v1/%2/user/%3/posts")
                                .arg(m_baseUrl, artist.service(), artist.id());
                qDebug() << "Trying alternative URL:" << altUrl;
                
                QNetworkRequest altRequest = createRequest(altUrl);
                QNetworkReply* altReply = nullptr;
                {
                    LOCK_MUTEX(NetworkRequests);
                    altReply = m_networkManager->get(altRequest);
                    if (altReply) {
                        m_replyTypes[altReply] = "artistPosts";
                        m_replyLimits[altReply] = limit;
                        m_replyOffsets[altReply] = offset;
                        m_replyArtists[altReply] = artist;
                    }
                }
                if (altReply) {
                    // Clean up current request data
                    {
                        LOCK_MUTEX(NetworkRequests);
                        m_replyTypes.remove(reply);
                        m_replyLimits.remove(reply);
                        m_replyOffsets.remove(reply);
                        m_replyArtists.remove(reply);
                    }
                    reply->deleteLater();
                    return; // Wait for alternative request response
                } else {
                    qDebug() << "Failed to create alternative request";
                    emit error(QString("API endpoint not found for artist %1 (%2/%3). Error: %4").arg(artist.name(), artist.service(), artist.id(), errorMsg));
                    {
                        LOCK_MUTEX(NetworkRequests);
                        m_replyTypes.remove(reply);
                        m_replyLimits.remove(reply);
                        m_replyOffsets.remove(reply);
                        m_replyArtists.remove(reply);
                    }
                    reply->deleteLater();
                    return;
                }
            }
        }
        
        qDebug() << "Parsing posts from JSON...";
        QList<Post> posts = parsePostsFromJson(data);
        qDebug() << "Parsed" << posts.size() << "posts, emitting signal";
        
        if (replyType == "allArtistPosts") {
            emit allArtistPostsLoaded(posts, artist);
        } else {
            emit postsFound(posts);
        }
    } else if (replyType == "post") {
        QJsonParseError parseError;
        QJsonDocument doc = QJsonDocument::fromJson(data, &parseError);
        if (parseError.error == QJsonParseError::NoError && doc.isObject()) {
            QJsonObject rootObj = doc.object();
            // API возвращает {"post": {...}}, нужно извлечь объект post
            if (rootObj.contains("post") && rootObj["post"].isObject()) {
                QJsonObject postObj = rootObj["post"].toObject();
                Post post = parsePostFromJson(postObj);
                qDebug() << "Post parsed, title:" << post.title();
                emit postLoaded(post);
            } else {
                // Если структура другая, пробуем парсить напрямую
                Post post = parsePostFromJson(rootObj);
                qDebug() << "Post parsed (direct), title:" << post.title();
                emit postLoaded(post);
            }
        } else {
            qDebug() << "Failed to parse post JSON:" << parseError.errorString();
            emit error(QString("Failed to parse post: %1").arg(parseError.errorString()));
        }
    } else if (replyType == "artistInfo") {
        QJsonDocument doc = QJsonDocument::fromJson(data);
        if (doc.isObject()) {
            Artist artist = parseArtistFromJson(doc.object());
            emit artistLoaded(artist);
        }
    } else {
        qDebug() << "Unknown reply type:" << replyType;
    }
    
    // Clean up reply data
    {
        LOCK_MUTEX(NetworkRequests);
        m_replyTypes.remove(reply);
        m_replyLimits.remove(reply);
        m_replyOffsets.remove(reply);
        m_replyArtists.remove(reply);
    }
    reply->deleteLater();
}


QList<Artist> KemonoParser::parseArtistsFromJson(const QByteArray& data, int limit, int offset)
{
    QList<Artist> artists;
    
    if (data.isEmpty()) {
        qDebug() << "ERROR: Empty data received";
        return artists;
    }
    
    QJsonParseError error;
    QJsonDocument doc = QJsonDocument::fromJson(data, &error);
    
    if (error.error != QJsonParseError::NoError) {
        qDebug() << "JSON parse error:" << error.errorString() << "at offset" << error.offset;
        qDebug() << "Data preview:" << QString::fromUtf8(data.left(500));
        return artists;
    }
    
    if (doc.isArray()) {
        QJsonArray array = doc.array();
        qDebug() << "JSON is array with" << array.size() << "items, applying limit:" << limit << "offset:" << offset;
        
        // API может вернуть весь массив, но мы парсим только нужный срез
        int startIndex = offset;
        int endIndex = (limit > 0) ? qMin(offset + limit, array.size()) : array.size();
        
        qDebug() << "Parsing artists from index" << startIndex << "to" << endIndex;
        
        for (int i = startIndex; i < endIndex; ++i) {
            const QJsonValue& value = array[i];
            if (value.isObject()) {
                QJsonObject obj = value.toObject();
                Artist artist = parseArtistFromJson(obj);
                artists.append(artist);
            }
        }
    } else if (doc.isObject()) {
        QJsonObject obj = doc.object();
        qDebug() << "JSON is object, keys:" << obj.keys();
        
        // Проверяем различные возможные ключи
        if (obj.contains("creators") && obj["creators"].isArray()) {
            QJsonArray array = obj["creators"].toArray();
            qDebug() << "Found 'creators' array with" << array.size() << "items, applying limit:" << limit << "offset:" << offset;
            int startIndex = offset;
            int endIndex = (limit > 0) ? qMin(offset + limit, array.size()) : array.size();
            for (int i = startIndex; i < endIndex; ++i) {
                const QJsonValue& value = array[i];
                if (value.isObject()) {
                    artists.append(parseArtistFromJson(value.toObject()));
                }
            }
        } else if (obj.contains("data") && obj["data"].isArray()) {
            QJsonArray array = obj["data"].toArray();
            qDebug() << "Found 'data' array with" << array.size() << "items, applying limit:" << limit << "offset:" << offset;
            int startIndex = offset;
            int endIndex = (limit > 0) ? qMin(offset + limit, array.size()) : array.size();
            for (int i = startIndex; i < endIndex; ++i) {
                const QJsonValue& value = array[i];
                if (value.isObject()) {
                    artists.append(parseArtistFromJson(value.toObject()));
                }
            }
        } else {
            qDebug() << "JSON is object but no known array key found";
            qDebug() << "All keys:" << obj.keys();
        }
    } else {
        qDebug() << "JSON is neither array nor object";
    }
    
    qDebug() << "Total artists parsed:" << artists.size();
    return artists;
}

QList<Post> KemonoParser::parsePostsFromJson(const QByteArray& data)
{
    QList<Post> posts;
    QJsonDocument doc = QJsonDocument::fromJson(data);
    
    if (doc.isArray()) {
        QJsonArray array = doc.array();
        for (const QJsonValue& value : array) {
            if (value.isObject()) {
                QJsonObject obj = value.toObject();
                Post post = parsePostFromJson(obj);
                
                // Если нет thumbnail, используем file.path как thumbnail
                if (post.thumbnail().isEmpty() && obj.contains("file") && obj["file"].isObject()) {
                    QJsonObject fileObj = obj["file"].toObject();
                    if (fileObj.contains("path")) {
                        post.setThumbnail(fileObj["path"].toString());
                    }
                }
                
                posts.append(post);
            }
        }
    }
    
    return posts;
}

Artist KemonoParser::parseArtistFromJson(const QJsonObject& obj)
{
    Artist artist;
    
    // Парсим id - может быть строкой или числом
    if (obj.contains("id")) {
        QJsonValue idValue = obj["id"];
        if (idValue.isString()) {
            artist.setId(idValue.toString());
        } else if (idValue.isDouble()) {
            artist.setId(QString::number(static_cast<qint64>(idValue.toDouble())));
        }
    }
    
    artist.setService(obj.value("service").toString());
    artist.setName(obj.value("name").toString());
    
    // indexed и updated могут быть числами (timestamp) или строками
    QJsonValue indexedValue = obj.value("indexed");
    if (indexedValue.isString()) {
        artist.setIndexed(indexedValue.toString());
    } else if (indexedValue.isDouble()) {
        artist.setIndexed(QString::number(static_cast<qint64>(indexedValue.toDouble())));
    }
    
    QJsonValue updatedValue = obj.value("updated");
    if (updatedValue.isString()) {
        artist.setUpdated(updatedValue.toString());
    } else if (updatedValue.isDouble()) {
        artist.setUpdated(QString::number(static_cast<qint64>(updatedValue.toDouble())));
    }
    
    if (obj.contains("avatar")) {
        artist.setAvatar(obj["avatar"].toString());
    }
    
    artist.ensureUrl();
    
    return artist;
}

Post KemonoParser::parsePostFromJson(const QJsonObject& obj)
{
    Post post;
    post.setId(obj["id"].toString());
    post.setTitle(obj["title"].toString());
    post.setContent(obj["content"].toString());
    post.setPublished(obj["published"].toString());
    post.setEdited(obj["edited"].toString());
    post.setAuthor(obj["user"].toString());
    post.setService(obj["service"].toString());
    
    // Формируем URL поста
    QString postUrl = QString("https://kemono.cr/%1/user/%2/post/%3")
                      .arg(post.service(), post.author(), post.id());
    post.setUrl(postUrl);
    
    if (obj.contains("thumbnail")) {
        post.setThumbnail(obj["thumbnail"].toString());
    }
    
    // Парсим attachments, embeds, files
    if (obj.contains("attachments") && obj["attachments"].isArray()) {
        QList<QVariantMap> attachments;
        for (const QJsonValue& val : obj["attachments"].toArray()) {
            if (val.isObject()) {
                QVariantMap map = val.toObject().toVariantMap();
                attachments.append(map);
            }
        }
        post.setAttachments(attachments);
    }
    
    if (obj.contains("embeds") && obj["embeds"].isArray()) {
        QList<QVariantMap> embeds;
        for (const QJsonValue& val : obj["embeds"].toArray()) {
            if (val.isObject()) {
                QVariantMap map = val.toObject().toVariantMap();
                embeds.append(map);
            }
        }
        post.setEmbeds(embeds);
    }
    
    if (obj.contains("file") && obj["file"].isObject()) {
        QList<QVariantMap> files;
        QVariantMap map = obj["file"].toObject().toVariantMap();
        files.append(map);
        post.setFiles(files);
        
        // Если нет thumbnail, используем первый файл как thumbnail
        if (post.thumbnail().isEmpty() && !files.isEmpty() && map.contains("path")) {
            post.setThumbnail(map["path"].toString());
        }
    }
    
    return post;
}

