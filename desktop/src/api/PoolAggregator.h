#pragma once

#include "core/Models.h"

#include <QObject>
#include <QSet>

class PoolAggregator : public QObject {
    Q_OBJECT
public:
    explicit PoolAggregator(QObject *parent = nullptr);

    void reset(const QVector<BooruServer> &servers, const QString &query);
    void loadMore();

    bool isLoading() const { return m_pending > 0; }

signals:
    void pageReady(const QVector<BooruPool> &pools, const QString &error);
    void loadingChanged(bool loading);

private:
    void fetchPage();
    void finishPage();

    struct Cursor {
        BooruServer server;
        int nextPage = 1;
        bool hasMore = true;
        QVector<BooruPool> fetched;
        QString error;
    };

    QVector<Cursor> m_cursors;
    QSet<QString> m_seen;
    QString m_query;
    int m_pending = 0;
    bool m_hasMore = true;
    int m_generation = 0;
};
