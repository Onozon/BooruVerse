#pragma once

#include "core/Models.h"

#include <QObject>
#include <QSet>

class FeedAggregator : public QObject {
    Q_OBJECT
public:
    explicit FeedAggregator(QObject *parent = nullptr);

    void reset(const QVector<BooruServer> &servers, const QString &tags, RatingFilter filter);
    void loadPopular(const QVector<BooruServer> &servers, PopularPeriod period, RatingFilter filter);
    void loadPersonal(const QVector<BooruServer> &servers, const QVector<QStringList> &tagSets,
                      RatingFilter filter);
    void loadPool(const BooruServer &server, int poolId, RatingFilter filter);
    void loadMore();

    bool isLoading() const { return m_pending > 0; }
    bool hasMore() const { return m_hasMore; }

signals:
    void pageReady(const QVector<BooruPost> &posts, const QString &error);
    void loadingChanged(bool loading);

private:
    void fetchPage();
    void finishPage();

    struct Cursor {
        BooruServer server;
        QString tags;
        int nextPage = 1;
        bool hasMore = true;
        QVector<BooruPost> fetched;
        QString error;
    };

    QVector<Cursor> m_cursors;
    QSet<QString> m_seen;
    QSet<QString> m_seenMd5;
    QString m_tags;
    RatingFilter m_filter = RatingFilter::All;
    bool m_popular = false;
    bool m_personal = false;
    bool m_pool = false;
    int m_poolId = 0;
    PopularPeriod m_period = PopularPeriod::Day;
    int m_pending = 0;
    bool m_hasMore = true;
    int m_generation = 0;
    int m_emptyRetries = 0;
};
