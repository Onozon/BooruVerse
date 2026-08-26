#include "api/FeedAggregator.h"

#include "api/BooruClient.h"

#include <algorithm>

#include <QHash>

FeedAggregator::FeedAggregator(QObject *parent)
    : QObject(parent) {
}

void FeedAggregator::reset(const QVector<BooruServer> &servers, const QString &tags, RatingFilter filter) {
    ++m_generation;
    m_cursors.clear();
    m_seen.clear();
    m_seenMd5.clear();
    m_tags = tags;
    m_filter = filter;
    m_popular = false;
    m_personal = false;
    m_pool = false;
    m_poolId = 0;
    m_hasMore = !servers.isEmpty();
    m_emptyRetries = 0;
    for (const BooruServer &server : servers)
        m_cursors.append(Cursor{server, tags, 1, true, {}, {}});
    fetchPage();
}

void FeedAggregator::loadPopular(const QVector<BooruServer> &servers, PopularPeriod period, RatingFilter filter) {
    ++m_generation;
    m_cursors.clear();
    m_seen.clear();
    m_seenMd5.clear();
    m_tags.clear();
    m_filter = filter;
    m_popular = true;
    m_personal = false;
    m_pool = false;
    m_poolId = 0;
    m_period = period;
    m_hasMore = false;
    for (const BooruServer &server : servers) {
        if (BooruClient::supportsPopular(server.flavor))
            m_cursors.append(Cursor{server, {}, 1, true, {}, {}});
    }
    fetchPage();
}

void FeedAggregator::loadPersonal(const QVector<BooruServer> &servers, const QVector<QStringList> &tagSets,
                                  RatingFilter filter) {
    ++m_generation;
    m_cursors.clear();
    m_seen.clear();
    m_seenMd5.clear();
    m_tags.clear();
    m_filter = filter;
    m_popular = false;
    m_personal = true;
    m_pool = false;
    m_poolId = 0;
    m_hasMore = !servers.isEmpty() && !tagSets.isEmpty();
    m_emptyRetries = 0;
    for (const QStringList &tags : tagSets) {
        const QString joined = tags.join(QLatin1Char(' '));
        for (const BooruServer &server : servers)
            m_cursors.append(Cursor{server, joined, 1, true, {}, {}});
    }
    fetchPage();
}

void FeedAggregator::loadPool(const BooruServer &server, int poolId, RatingFilter filter) {
    ++m_generation;
    m_cursors.clear();
    m_seen.clear();
    m_seenMd5.clear();
    m_tags.clear();
    m_filter = filter;
    m_popular = false;
    m_personal = false;
    m_pool = true;
    m_poolId = poolId;
    m_hasMore = poolId > 0;
    if (poolId > 0)
        m_cursors.append(Cursor{server, {}, 1, true, {}, {}});
    fetchPage();
}

void FeedAggregator::loadMore() {
    if (m_popular || m_pending > 0 || !m_hasMore)
        return;
    fetchPage();
}

void FeedAggregator::fetchPage() {
    m_pending = 0;
    for (int index = 0; index < m_cursors.size(); ++index) {
        Cursor &cursor = m_cursors[index];
        if (!cursor.hasMore)
            continue;
        ++m_pending;
        cursor.fetched.clear();
        cursor.error.clear();
        const int generation = m_generation;
        auto handler = [this, index, generation](QVector<BooruPost> posts, QString error) {
            if (generation != m_generation || index < 0 || index >= m_cursors.size())
                return;
            Cursor &target = m_cursors[index];
            target.fetched = posts;
            target.error = error;
            if (m_popular || posts.isEmpty() || (!m_pool && posts.size() < 40))
                target.hasMore = false;
            else
                target.nextPage += 1;
            --m_pending;
            if (m_pending == 0)
                finishPage();
        };
        if (m_popular)
            BooruClient::fetchPopular(cursor.server, m_period, handler);
        else if (m_pool)
            BooruClient::fetchPoolPosts(cursor.server, m_poolId, cursor.nextPage, handler);
        else {
            const QString query = queryWithRating(cursor.tags, m_filter, cursor.server.flavor);
            BooruClient::fetchPosts(cursor.server, query, cursor.nextPage, 40, handler);
        }
    }
    emit loadingChanged(m_pending > 0);
    if (m_pending == 0)
        finishPage();
}

void FeedAggregator::finishPage() {
    QVector<BooruPost> merged;
    QHash<QString, int> md5Index;
    int row = 0;
    bool added = true;
    while (added) {
        added = false;
        for (Cursor &cursor : m_cursors) {
            if (row >= cursor.fetched.size())
                continue;
            added = true;
            BooruPost post = cursor.fetched[row];
            if (!post.allowedBy(m_filter))
                continue;
            if (m_seen.contains(post.globalId()))
                continue;
            m_seen.insert(post.globalId());
            if (!post.md5.isEmpty()) {
                if (m_seenMd5.contains(post.md5)) {
                    const auto it = md5Index.constFind(post.md5);
                    if (it != md5Index.cend())
                        merged[it.value()].duplicateCount += 1;
                    continue;
                }
                m_seenMd5.insert(post.md5);
                md5Index.insert(post.md5, merged.size());
            }
            merged.append(post);
        }
        ++row;
    }

    if (m_personal) {
        std::sort(merged.begin(), merged.end(), [](const BooruPost &a, const BooruPost &b) {
            if (a.createdAt != b.createdAt)
                return a.createdAt > b.createdAt;
            return a.globalId() > b.globalId();
        });
    }

    m_hasMore = false;
    QStringList errors;
    for (const Cursor &cursor : m_cursors) {
        if (cursor.hasMore)
            m_hasMore = true;
        if (!cursor.error.isEmpty())
            errors.append(cursor.server.host + QStringLiteral(": ") + cursor.error);
    }

    if (merged.isEmpty() && m_hasMore && !m_popular && m_emptyRetries < 6) {
        ++m_emptyRetries;
        fetchPage();
        return;
    }
    m_emptyRetries = 0;
    emit loadingChanged(false);
    emit pageReady(merged, errors.join(QStringLiteral("\n")));
}
