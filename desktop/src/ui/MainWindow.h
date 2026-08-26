#pragma once

#include "core/Models.h"

#include <QMainWindow>
#include <QVector>

class FeedAggregator;
class PoolAggregator;
class PoolListWidget;
class PostGridWidget;
class TagSidebar;
class ThumbnailCache;
class ViewerDialog;
class QAction;
class QComboBox;
class QLabel;
class QSlider;
class QStackedWidget;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(QWidget *parent = nullptr);

private:
    enum Section { Browse = 0, Feed = 1, Favorites = 2, Pools = 3 };

    struct Session {
        QVector<BooruPost> posts;
        int scroll = 0;
        QString fingerprint;
    };

    void reloadCurrent();
    void reloadBrowse();
    void reloadFeed();
    void reloadFavorites();
    void reloadPools();
    void openPool(const BooruPool &pool);
    void appendPosts(const QVector<BooruPost> &posts, const QString &error);
    void handlePage(FeedAggregator *source, const QVector<BooruPost> &posts, const QString &error);
    void appendPools(const QVector<BooruPool> &pools, const QString &error);
    void updateChrome();
    void applyViewerTag(const QString &tag);
    void refreshPageTags();
    void applyGallery();
    void persistGalleryScale(int extent);
    void stashCurrent();
    void restoreOrReload();
    void showSession(const Session &session);
    void refreshFavoriteSnapshots();
    void savePost(const BooruPost &post);
    void openPostSite(const BooruPost &post);
    QString fingerprint() const;
    FeedAggregator *activeAggregator() const;
    Section ownerFor(FeedAggregator *aggregator) const;
    RatingFilter currentFilter() const;
    PopularPeriod currentPeriod() const;
    FeedChannel currentChannel() const;
    Section currentSection() const;
    GallerySection currentGallerySection() const;
    QVector<BooruServer> poolServers() const;
    bool isPersonalFeed() const;

    FeedAggregator *m_browseAgg = nullptr;
    FeedAggregator *m_feedAgg = nullptr;
    FeedAggregator *m_poolAgg = nullptr;
    PoolAggregator *m_pools = nullptr;
    ThumbnailCache *m_cache = nullptr;
    PostGridWidget *m_grid = nullptr;
    ViewerDialog *m_viewer = nullptr;
    TagSidebar *m_tags = nullptr;
    PoolListWidget *m_poolList = nullptr;
    QStackedWidget *m_left = nullptr;
    QComboBox *m_section = nullptr;
    QComboBox *m_period = nullptr;
    QComboBox *m_rating = nullptr;
    QComboBox *m_tiling = nullptr;
    QSlider *m_scale = nullptr;
    QAction *m_sidebarToggle = nullptr;
    QLabel *m_status = nullptr;
    QVector<BooruPost> m_posts;
    Session m_sessions[4];
    Section m_lastSection = Browse;
    bool m_loadingMore = false;
    bool m_poolDetail = false;
    bool m_refreshingFavorites = false;
    BooruPool m_openPool;
};
