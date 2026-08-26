#include "api/BooruClient.h"

#include "core/HttpClient.h"
#include "core/TagIndexStore.h"

#include <algorithm>

#include <QDateTime>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>

static QUrl baseUrl(const BooruServer &server) {
    return QUrl(QStringLiteral("https://") + server.host);
}

static QUrl firstUrl(const QStringList &candidates) {
    for (const QString &value : candidates) {
        if (!value.isEmpty())
            return QUrl(value);
    }
    return {};
}

static QString jsonString(const QJsonObject &object, const QString &key) {
    const QJsonValue value = object.value(key);
    if (value.isString())
        return value.toString();
    if (value.isDouble())
        return QString::number(value.toInt());
    return {};
}

static int jsonInt(const QJsonObject &object, const QString &key, int fallback = 0) {
    const QJsonValue value = object.value(key);
    if (value.isDouble())
        return value.toInt();
    if (value.isString())
        return value.toString().toInt();
    return fallback;
}

static QStringList splitTags(const QString &raw) {
    return raw.split(QLatin1Char(' '), Qt::SkipEmptyParts);
}

static qint64 parseTimestamp(const QJsonValue &value) {
    if (value.isDouble()) {
        const double number = value.toDouble();
        if (number > 1e12)
            return qint64(number / 1000.0);
        if (number > 1e9)
            return qint64(number);
        return 0;
    }
    if (value.isString()) {
        const QString text = value.toString();
        bool ok = false;
        const double number = text.toDouble(&ok);
        if (ok) {
            if (number > 1e12)
                return qint64(number / 1000.0);
            if (number > 1e9)
                return qint64(number);
        }
        QDateTime date = QDateTime::fromString(text, Qt::ISODate);
        if (date.isValid())
            return date.toSecsSinceEpoch();
        date = QDateTime::fromString(text, QStringLiteral("yyyy-MM-dd HH:mm:ss"));
        if (date.isValid())
            return date.toSecsSinceEpoch();
        return 0;
    }
    if (value.isObject())
        return parseTimestamp(value.toObject().value(QStringLiteral("s")));
    return 0;
}

static qint64 createdAtFrom(const QJsonObject &object) {
    const qint64 created = parseTimestamp(object.value(QStringLiteral("created_at")));
    if (created > 0)
        return created;
    return parseTimestamp(object.value(QStringLiteral("change")));
}

static BooruPost moebooruPost(const QJsonObject &object, const QString &serverId) {
    BooruPost post;
    post.serverId = serverId;
    post.id = jsonInt(object, QStringLiteral("id"));
    post.md5 = jsonString(object, QStringLiteral("md5"));
    post.tags = splitTags(jsonString(object, QStringLiteral("tags")));
    post.rating = ratingFromRaw(jsonString(object, QStringLiteral("rating")), ApiFlavor::Moebooru);
    post.score = jsonInt(object, QStringLiteral("score"));
    post.width = jsonInt(object, QStringLiteral("width"));
    post.height = jsonInt(object, QStringLiteral("height"));
    post.previewUrl = firstUrl({jsonString(object, QStringLiteral("preview_url"))});
    post.sampleUrl = firstUrl({jsonString(object, QStringLiteral("sample_url"))});
    post.fileUrl = firstUrl({jsonString(object, QStringLiteral("file_url"))});
    post.fileExt = jsonString(object, QStringLiteral("file_ext"));
    post.sourceUrl = firstUrl({jsonString(object, QStringLiteral("source"))});
    post.createdAt = createdAtFrom(object);
    return post;
}

static QString mediaVariant(const QJsonObject &object, const QString &type) {
    const QJsonObject asset = object.value(QStringLiteral("media_asset")).toObject();
    const QJsonArray variants = asset.value(QStringLiteral("variants")).toArray();
    for (const QJsonValue &value : variants) {
        const QJsonObject variant = value.toObject();
        if (variant.value(QStringLiteral("type")).toString() == type)
            return variant.value(QStringLiteral("url")).toString();
    }
    return {};
}

static BooruPost danbooruPost(const QJsonObject &object, const QString &serverId) {
    BooruPost post;
    post.serverId = serverId;
    post.id = jsonInt(object, QStringLiteral("id"));
    post.md5 = jsonString(object, QStringLiteral("md5"));
    post.tags = splitTags(jsonString(object, QStringLiteral("tag_string")));
    post.rating = ratingFromRaw(jsonString(object, QStringLiteral("rating")), ApiFlavor::Danbooru2);
    post.score = jsonInt(object, QStringLiteral("score"));
    post.width = jsonInt(object, QStringLiteral("image_width"));
    post.height = jsonInt(object, QStringLiteral("image_height"));
    post.previewUrl = firstUrl({
        jsonString(object, QStringLiteral("preview_file_url")),
        mediaVariant(object, QStringLiteral("360x360")),
        mediaVariant(object, QStringLiteral("180x180")),
        jsonString(object, QStringLiteral("large_file_url")),
    });
    post.sampleUrl = firstUrl({
        jsonString(object, QStringLiteral("large_file_url")),
        mediaVariant(object, QStringLiteral("sample")),
        mediaVariant(object, QStringLiteral("720x720")),
        jsonString(object, QStringLiteral("file_url")),
    });
    post.fileUrl = firstUrl({
        jsonString(object, QStringLiteral("file_url")),
        mediaVariant(object, QStringLiteral("original")),
        jsonString(object, QStringLiteral("large_file_url")),
    });
    post.fileExt = jsonString(object, QStringLiteral("file_ext"));
    post.sourceUrl = firstUrl({jsonString(object, QStringLiteral("source"))});
    post.createdAt = createdAtFrom(object);
    return post;
}

static BooruPost gelbooruPost(const QJsonObject &object, const QString &serverId) {
    BooruPost post;
    post.serverId = serverId;
    post.id = jsonInt(object, QStringLiteral("id"));
    post.md5 = jsonString(object, QStringLiteral("md5"));
    post.tags = splitTags(jsonString(object, QStringLiteral("tags")));
    post.rating = ratingFromRaw(jsonString(object, QStringLiteral("rating")), ApiFlavor::Gelbooru);
    post.score = jsonInt(object, QStringLiteral("score"));
    post.width = jsonInt(object, QStringLiteral("width"));
    post.height = jsonInt(object, QStringLiteral("height"));
    post.previewUrl = firstUrl({jsonString(object, QStringLiteral("preview_url"))});
    post.sampleUrl = firstUrl({jsonString(object, QStringLiteral("sample_url"))});
    post.fileUrl = firstUrl({jsonString(object, QStringLiteral("file_url"))});
    const QUrl file = post.fileUrl;
    post.fileExt = file.path().section(QLatin1Char('.'), -1);
    post.sourceUrl = firstUrl({jsonString(object, QStringLiteral("source"))});
    post.createdAt = createdAtFrom(object);
    return post;
}

static QJsonArray asArray(const QJsonValue &value) {
    if (value.isArray())
        return value.toArray();
    if (value.isObject())
        return QJsonArray{value.toObject()};
    return {};
}

static QJsonArray decodeArray(const QByteArray &data) {
    const QJsonDocument document = QJsonDocument::fromJson(data);
    if (document.isArray())
        return document.array();
    if (document.isObject()) {
        const QJsonObject object = document.object();
        if (object.contains(QStringLiteral("post")))
            return asArray(object.value(QStringLiteral("post")));
        if (object.contains(QStringLiteral("tag")))
            return asArray(object.value(QStringLiteral("tag")));
    }
    return {};
}

static QVariantMap withAuth(const BooruServer &server, QVariantMap query) {
    if (server.flavor == ApiFlavor::Danbooru2 && !server.apiKey.isEmpty() && !server.userId.isEmpty()) {
        query.insert(QStringLiteral("login"), server.userId);
        query.insert(QStringLiteral("api_key"), server.apiKey);
    }
    if (server.flavor == ApiFlavor::Gelbooru) {
        if (!server.apiKey.isEmpty())
            query.insert(QStringLiteral("api_key"), server.apiKey);
        if (!server.userId.isEmpty())
            query.insert(QStringLiteral("user_id"), server.userId);
    }
    return query;
}

bool BooruClient::supportsPopular(ApiFlavor flavor) {
    return flavor == ApiFlavor::Moebooru || flavor == ApiFlavor::Danbooru2;
}

bool BooruClient::supportsPools(ApiFlavor flavor) {
    return flavor == ApiFlavor::Moebooru;
}

void BooruClient::fetchPosts(const BooruServer &server, const QString &tags, int page, int limit,
                             PostsCallback callback) {
    QUrl url;
    QVariantMap query;
    switch (server.flavor) {
    case ApiFlavor::Moebooru:
        url = baseUrl(server).resolved(QUrl(QStringLiteral("/post.json")));
        query = {{QStringLiteral("tags"), tags},
                 {QStringLiteral("page"), QString::number(qMax(page, 1))},
                 {QStringLiteral("limit"), QString::number(qBound(1, limit, 100))}};
        break;
    case ApiFlavor::Danbooru2:
        url = baseUrl(server).resolved(QUrl(QStringLiteral("/posts.json")));
        query = {{QStringLiteral("tags"), tags},
                 {QStringLiteral("page"), QString::number(qMax(page, 1))},
                 {QStringLiteral("limit"), QString::number(qBound(1, limit, 200))}};
        break;
    case ApiFlavor::Gelbooru:
        url = baseUrl(server).resolved(QUrl(QStringLiteral("/index.php")));
        query = {{QStringLiteral("page"), QStringLiteral("dapi")},
                 {QStringLiteral("s"), QStringLiteral("post")},
                 {QStringLiteral("q"), QStringLiteral("index")},
                 {QStringLiteral("json"), QStringLiteral("1")},
                 {QStringLiteral("tags"), tags},
                 {QStringLiteral("pid"), QString::number(qMax(page - 1, 0))},
                 {QStringLiteral("limit"), QString::number(qBound(1, limit, 100))}};
        break;
    }

    HttpClient::instance().get(url, withAuth(server, query), [server, callback](QByteArray data, QString error) {
        if (!error.isEmpty()) {
            callback({}, error);
            return;
        }
        QVector<BooruPost> posts;
        for (const QJsonValue &value : decodeArray(data)) {
            const QJsonObject object = value.toObject();
            BooruPost post;
            switch (server.flavor) {
            case ApiFlavor::Moebooru:
                post = moebooruPost(object, server.host);
                break;
            case ApiFlavor::Danbooru2:
                post = danbooruPost(object, server.host);
                break;
            case ApiFlavor::Gelbooru:
                post = gelbooruPost(object, server.host);
                break;
            }
            if (post.id > 0)
                posts.append(post);
        }
        callback(posts, {});
    });
}

void BooruClient::fetchPopular(const BooruServer &server, PopularPeriod period, PostsCallback callback) {
    if (!supportsPopular(server.flavor)) {
        callback({}, {});
        return;
    }

    QUrl url;
    QVariantMap query;
    if (server.flavor == ApiFlavor::Moebooru) {
        url = baseUrl(server).resolved(QUrl(QStringLiteral("/post/popular_recent.json")));
        query.insert(QStringLiteral("period"), periodQuery(period, server.flavor));
    } else {
        url = baseUrl(server).resolved(QUrl(QStringLiteral("/explore/posts/popular.json")));
        query.insert(QStringLiteral("scale"), periodQuery(period, server.flavor));
    }

    HttpClient::instance().get(url, withAuth(server, query), [server, callback](QByteArray data, QString error) {
        if (!error.isEmpty()) {
            callback({}, error);
            return;
        }
        QVector<BooruPost> posts;
        for (const QJsonValue &value : decodeArray(data)) {
            const QJsonObject object = value.toObject();
            const BooruPost post = server.flavor == ApiFlavor::Moebooru
                ? moebooruPost(object, server.host)
                : danbooruPost(object, server.host);
            if (post.id > 0)
                posts.append(post);
        }
        callback(posts, {});
    });
}

void BooruClient::suggestTags(const BooruServer &server, const QString &fragment, TagsCallback callback) {
    const QString trimmed = fragment.trimmed();
    if (trimmed.isEmpty()) {
        callback({}, {});
        return;
    }

    QUrl url;
    QVariantMap query;
    switch (server.flavor) {
    case ApiFlavor::Moebooru:
        url = baseUrl(server).resolved(QUrl(QStringLiteral("/tag.json")));
        query = {{QStringLiteral("name"), trimmed + QLatin1Char('*')},
                 {QStringLiteral("order"), QStringLiteral("count")},
                 {QStringLiteral("limit"), QStringLiteral("24")}};
        break;
    case ApiFlavor::Danbooru2:
        url = baseUrl(server).resolved(QUrl(QStringLiteral("/tags.json")));
        query = {{QStringLiteral("search[name_matches]"), trimmed + QLatin1Char('*')},
                 {QStringLiteral("search[order]"), QStringLiteral("count")},
                 {QStringLiteral("limit"), QStringLiteral("20")}};
        break;
    case ApiFlavor::Gelbooru:
        url = baseUrl(server).resolved(QUrl(QStringLiteral("/index.php")));
        query = {{QStringLiteral("page"), QStringLiteral("dapi")},
                 {QStringLiteral("s"), QStringLiteral("tag")},
                 {QStringLiteral("q"), QStringLiteral("index")},
                 {QStringLiteral("json"), QStringLiteral("1")},
                 {QStringLiteral("name_pattern"), QLatin1Char('%') + trimmed + QLatin1Char('%')},
                 {QStringLiteral("orderby"), QStringLiteral("count")},
                 {QStringLiteral("limit"), QStringLiteral("20")}};
        break;
    }

    HttpClient::instance().get(url, withAuth(server, query), [callback](QByteArray data, QString error) {
        if (!error.isEmpty()) {
            callback({}, error);
            return;
        }
        QVector<BooruTag> tags;
        for (const QJsonValue &value : decodeArray(data)) {
            const QJsonObject object = value.toObject();
            BooruTag tag;
            tag.name = jsonString(object, QStringLiteral("name"));
            tag.postCount = jsonInt(object, QStringLiteral("count"), jsonInt(object, QStringLiteral("post_count")));
            tag.type = tagTypeFromRaw(jsonInt(object, QStringLiteral("type"),
                                              jsonInt(object, QStringLiteral("category"))));
            if (!tag.name.isEmpty())
                tags.append(tag);
        }
        TagIndexStore::instance().remember(tags);
        callback(tags, {});
    });
}

void BooruClient::fetchTagTypes(const BooruServer &server, const QStringList &names, TagsCallback callback) {
    QStringList cleaned;
    for (const QString &name : names) {
        if (!name.trimmed().isEmpty())
            cleaned.append(name.trimmed());
    }
    if (cleaned.isEmpty()) {
        callback({}, {});
        return;
    }

    QUrl url;
    QVariantMap query;
    switch (server.flavor) {
    case ApiFlavor::Gelbooru:
        url = baseUrl(server).resolved(QUrl(QStringLiteral("/index.php")));
        query = {{QStringLiteral("page"), QStringLiteral("dapi")},
                 {QStringLiteral("s"), QStringLiteral("tag")},
                 {QStringLiteral("q"), QStringLiteral("index")},
                 {QStringLiteral("json"), QStringLiteral("1")},
                 {QStringLiteral("names"), cleaned.join(QLatin1Char(' '))}};
        break;
    case ApiFlavor::Danbooru2:
        url = baseUrl(server).resolved(QUrl(QStringLiteral("/tags.json")));
        query = {{QStringLiteral("search[name_comma]"), cleaned.join(QLatin1Char(','))},
                 {QStringLiteral("limit"), QString::number(cleaned.size())}};
        break;
    case ApiFlavor::Moebooru:
        url = baseUrl(server).resolved(QUrl(QStringLiteral("/tag.json")));
        query = {{QStringLiteral("name"), cleaned.first()}, {QStringLiteral("limit"), QStringLiteral("1")}};
        break;
    }

    HttpClient::instance().get(url, withAuth(server, query), [callback](QByteArray data, QString error) {
        if (!error.isEmpty()) {
            callback({}, error);
            return;
        }
        QVector<BooruTag> tags;
        for (const QJsonValue &value : decodeArray(data)) {
            const QJsonObject object = value.toObject();
            BooruTag tag;
            tag.name = jsonString(object, QStringLiteral("name"));
            tag.postCount = jsonInt(object, QStringLiteral("count"), jsonInt(object, QStringLiteral("post_count")));
            tag.type = tagTypeFromRaw(jsonInt(object, QStringLiteral("type"),
                                              jsonInt(object, QStringLiteral("category"))));
            if (!tag.name.isEmpty())
                tags.append(tag);
        }
        TagIndexStore::instance().remember(tags);
        callback(tags, {});
    });
}

void BooruClient::fetchPost(const BooruServer &server, int id, PostsCallback callback) {
    if (id <= 0) {
        callback({}, {});
        return;
    }
    if (server.flavor == ApiFlavor::Danbooru2) {
        const QUrl url = baseUrl(server).resolved(QUrl(QStringLiteral("/posts/%1.json").arg(id)));
        HttpClient::instance().get(url, withAuth(server, {}), [server, callback](QByteArray data, QString error) {
            if (!error.isEmpty()) {
                callback({}, error);
                return;
            }
            const QJsonDocument document = QJsonDocument::fromJson(data);
            const BooruPost post = danbooruPost(document.object(), server.host);
            callback(post.id > 0 ? QVector<BooruPost>{post} : QVector<BooruPost>{}, {});
        });
        return;
    }
    if (server.flavor == ApiFlavor::Gelbooru) {
        const QUrl url = baseUrl(server).resolved(QUrl(QStringLiteral("/index.php")));
        const QVariantMap query = {{QStringLiteral("page"), QStringLiteral("dapi")},
                                   {QStringLiteral("s"), QStringLiteral("post")},
                                   {QStringLiteral("q"), QStringLiteral("index")},
                                   {QStringLiteral("json"), QStringLiteral("1")},
                                   {QStringLiteral("id"), QString::number(id)}};
        HttpClient::instance().get(url, withAuth(server, query), [server, callback](QByteArray data, QString error) {
            if (!error.isEmpty()) {
                callback({}, error);
                return;
            }
            QVector<BooruPost> posts;
            for (const QJsonValue &value : decodeArray(data)) {
                const BooruPost post = gelbooruPost(value.toObject(), server.host);
                if (post.id > 0)
                    posts.append(post);
            }
            callback(posts, {});
        });
        return;
    }
    fetchPosts(server, QStringLiteral("id:%1").arg(id), 1, 1, callback);
}

void BooruClient::suggestFromServers(const QVector<BooruServer> &servers, const QStringList &selected,
                                     const QString &fragment, TagsCallback callback) {
    const QString trimmed = fragment.trimmed();
    if (trimmed.size() < 2 || servers.isEmpty()) {
        callback({}, {});
        return;
    }

    struct State {
        int pending = 0;
        QHash<QString, BooruTag> byName;
        QStringList errors;
    };
    auto *state = new State;
    state->pending = servers.size();
    for (const BooruServer &server : servers) {
        suggestTags(server, trimmed, [state, selected, callback](QVector<BooruTag> tags, QString error) {
            if (!error.isEmpty())
                state->errors.append(error);
            for (const BooruTag &tag : tags) {
                if (tag.name.isEmpty() || selected.contains(tag.name, Qt::CaseInsensitive))
                    continue;
                auto it = state->byName.find(tag.name);
                if (it == state->byName.end()) {
                    state->byName.insert(tag.name, tag);
                } else {
                    it->postCount += tag.postCount;
                }
            }
            if (--state->pending > 0)
                return;
            QVector<BooruTag> merged = state->byName.values();
            std::sort(merged.begin(), merged.end(), [](const BooruTag &a, const BooruTag &b) {
                if (a.postCount != b.postCount)
                    return a.postCount > b.postCount;
                return a.name < b.name;
            });
            if (merged.size() > 24)
                merged.resize(24);
            const QString joinedError = state->errors.join(QLatin1Char('\n'));
            delete state;
            callback(merged, joinedError);
        });
    }
}

void BooruClient::fetchPools(const BooruServer &server, const QString &query, int page, PoolsCallback callback) {
    if (!supportsPools(server.flavor)) {
        callback({}, {});
        return;
    }
    const QUrl url = baseUrl(server).resolved(QUrl(QStringLiteral("/pool.json")));
    QVariantMap queryMap = {{QStringLiteral("page"), QString::number(qMax(page, 1))}};
    if (!query.trimmed().isEmpty())
        queryMap.insert(QStringLiteral("query"), query.trimmed());

    HttpClient::instance().get(url, queryMap, [server, callback](QByteArray data, QString error) {
        if (!error.isEmpty()) {
            callback({}, error);
            return;
        }
        QVector<BooruPool> pools;
        for (const QJsonValue &value : decodeArray(data)) {
            const QJsonObject object = value.toObject();
            BooruPool pool;
            pool.serverId = server.host;
            pool.id = jsonInt(object, QStringLiteral("id"));
            pool.name = jsonString(object, QStringLiteral("name"));
            pool.postCount = jsonInt(object, QStringLiteral("post_count"),
                                     jsonInt(object, QStringLiteral("postCount")));
            pool.description = jsonString(object, QStringLiteral("description"));
            if (pool.id > 0)
                pools.append(pool);
        }
        callback(pools, {});
    });
}

void BooruClient::fetchPoolPosts(const BooruServer &server, int poolId, int page, PostsCallback callback) {
    if (!supportsPools(server.flavor) || poolId <= 0) {
        callback({}, {});
        return;
    }
    const QUrl url = baseUrl(server).resolved(QUrl(QStringLiteral("/pool/show.json")));
    const QVariantMap query = {{QStringLiteral("id"), QString::number(poolId)},
                               {QStringLiteral("page"), QString::number(qMax(page, 1))}};
    HttpClient::instance().get(url, query, [server, callback](QByteArray data, QString error) {
        if (!error.isEmpty()) {
            callback({}, error);
            return;
        }
        const QJsonDocument document = QJsonDocument::fromJson(data);
        QJsonArray array;
        if (document.isObject())
            array = document.object().value(QStringLiteral("posts")).toArray();
        else if (document.isArray())
            array = document.array();

        QVector<BooruPost> posts;
        for (const QJsonValue &value : array) {
            const BooruPost post = moebooruPost(value.toObject(), server.host);
            if (post.id > 0)
                posts.append(post);
        }
        callback(posts, {});
    });
}
