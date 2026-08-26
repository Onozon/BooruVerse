#pragma once

#include "core/Models.h"

#include <QObject>
#include <functional>

class BooruClient {
public:
    using PostsCallback = std::function<void(QVector<BooruPost> posts, QString error)>;
    using TagsCallback = std::function<void(QVector<BooruTag> tags, QString error)>;
    using PoolsCallback = std::function<void(QVector<BooruPool> pools, QString error)>;

    static void fetchPosts(const BooruServer &server, const QString &tags, int page, int limit,
                           PostsCallback callback);
    static void fetchPopular(const BooruServer &server, PopularPeriod period, PostsCallback callback);
    static void fetchPools(const BooruServer &server, const QString &query, int page, PoolsCallback callback);
    static void fetchPoolPosts(const BooruServer &server, int poolId, int page, PostsCallback callback);
    static void suggestTags(const BooruServer &server, const QString &fragment, TagsCallback callback);
    static void suggestFromServers(const QVector<BooruServer> &servers, const QStringList &selected,
                                   const QString &fragment, TagsCallback callback);
    static void fetchTagTypes(const BooruServer &server, const QStringList &names, TagsCallback callback);
    static void fetchPost(const BooruServer &server, int id, PostsCallback callback);
    static bool supportsPopular(ApiFlavor flavor);
    static bool supportsPools(ApiFlavor flavor);
};
