#include "api/PoolAggregator.h"

#include "api/BooruClient.h"

#include <QStringList>

PoolAggregator::PoolAggregator(QObject *parent)
    : QObject(parent) {
}

void PoolAggregator::reset(const QVector<BooruServer> &servers, const QString &query) {
    ++m_generation;
    m_cursors.clear();
    m_seen.clear();
    m_query = query;
    m_hasMore = false;
    for (const BooruServer &server : servers) {
        if (BooruClient::supportsPools(server.flavor))
            m_cursors.append(Cursor{server, 1, true, {}, {}});
    }
    fetchPage();
}

void PoolAggregator::loadMore() {
    if (m_pending > 0 || !m_hasMore)
        return;
    fetchPage();
}

void PoolAggregator::fetchPage() {
    m_pending = 0;
    for (int index = 0; index < m_cursors.size(); ++index) {
        Cursor &cursor = m_cursors[index];
        if (!cursor.hasMore)
            continue;
        ++m_pending;
        cursor.fetched.clear();
        cursor.error.clear();
        const int generation = m_generation;
        BooruClient::fetchPools(cursor.server, m_query, cursor.nextPage,
                                [this, index, generation](QVector<BooruPool> pools, QString error) {
                                    if (generation != m_generation || index < 0 || index >= m_cursors.size())
                                        return;
                                    Cursor &target = m_cursors[index];
                                    target.fetched = pools;
                                    target.error = error;
                                    if (pools.isEmpty())
                                        target.hasMore = false;
                                    else
                                        target.nextPage += 1;
                                    --m_pending;
                                    if (m_pending == 0)
                                        finishPage();
                                });
    }
    emit loadingChanged(m_pending > 0);
    if (m_pending == 0)
        finishPage();
}

void PoolAggregator::finishPage() {
    QVector<BooruPool> merged;
    int row = 0;
    bool added = true;
    while (added) {
        added = false;
        for (const Cursor &cursor : m_cursors) {
            if (row >= cursor.fetched.size())
                continue;
            added = true;
            const BooruPool &pool = cursor.fetched[row];
            if (m_seen.contains(pool.globalId()))
                continue;
            m_seen.insert(pool.globalId());
            merged.append(pool);
        }
        ++row;
    }

    m_hasMore = false;
    QStringList errors;
    for (const Cursor &cursor : m_cursors) {
        if (cursor.hasMore)
            m_hasMore = true;
        if (!cursor.error.isEmpty())
            errors.append(cursor.server.host + QStringLiteral(": ") + cursor.error);
    }

    emit loadingChanged(false);
    emit pageReady(merged, errors.join(QStringLiteral("\n")));
}
