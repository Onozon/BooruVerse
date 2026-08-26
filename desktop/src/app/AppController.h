#pragma once

#include "app/PostListModel.h"
#include "app/SimpleListModels.h"
#include "core/DownloadStore.h"
#include "core/GalleryLayout.h"
#include "core/Models.h"
#include "core/SelectionStore.h"

#include <QObject>
#include <QStringList>
#include <QVariantList>
#include <QVector>

class FeedAggregator;
class PoolAggregator;

class AppController : public QObject {
    Q_OBJECT
    Q_PROPERTY(int tab READ tab WRITE setTab NOTIFY tabChanged)
    Q_PROPERTY(bool compact READ compact NOTIFY compactChanged)
    Q_PROPERTY(double windowWidth READ windowWidth WRITE setWindowWidth NOTIFY compactChanged)
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY statusChanged)
    Q_PROPERTY(int feedChannel READ feedChannel WRITE setFeedChannel NOTIFY feedChannelChanged)
    Q_PROPERTY(int ratingFilter READ ratingFilter WRITE setRatingFilter NOTIFY settingsChanged)
    Q_PROPERTY(int tilingMode READ tilingMode WRITE setTilingMode NOTIFY settingsChanged)
    Q_PROPERTY(int tileExtent READ tileExtent WRITE setTileExtent NOTIFY settingsChanged)
    Q_PROPERTY(bool loadFullQuality READ loadFullQuality WRITE setLoadFullQuality NOTIFY settingsChanged)
    Q_PROPERTY(bool showsSidebar READ showsSidebar WRITE setShowsSidebar NOTIFY settingsChanged)
    Q_PROPERTY(bool browseOnSidebar READ browseOnSidebar WRITE setBrowseOnSidebar NOTIFY browseColumnChanged)
    Q_PROPERTY(bool favoritesOnSidebar READ favoritesOnSidebar WRITE setFavoritesOnSidebar NOTIFY browseColumnChanged)
    Q_PROPERTY(bool poolDetail READ poolDetail NOTIFY poolDetailChanged)
    Q_PROPERTY(QString poolTitle READ poolTitle NOTIFY poolDetailChanged)
    Q_PROPERTY(double scrollOffset READ scrollOffset WRITE setScrollOffset NOTIFY scrollOffsetChanged)
    Q_PROPERTY(int preferredTileWidth READ preferredTileWidth NOTIFY settingsChanged)
    Q_PROPERTY(bool viewerOpen READ viewerOpen NOTIFY viewerChanged)
    Q_PROPERTY(int viewerIndex READ viewerIndex NOTIFY viewerChanged)
    Q_PROPERTY(QString viewerUrl READ viewerUrl NOTIFY viewerChanged)
    Q_PROPERTY(QString viewerMeta READ viewerMeta NOTIFY viewerChanged)
    Q_PROPERTY(bool viewerFavorited READ viewerFavorited NOTIFY viewerChanged)
    Q_PROPERTY(bool viewerHasOriginal READ viewerHasOriginal NOTIFY viewerChanged)
    Q_PROPERTY(double viewerProgress READ viewerProgress NOTIFY viewerProgressChanged)
    Q_PROPERTY(bool peekOpen READ peekOpen NOTIFY peekChanged)
    Q_PROPERTY(QString peekUrl READ peekUrl NOTIFY peekChanged)
    Q_PROPERTY(QString peekMeta READ peekMeta NOTIFY peekChanged)
    Q_PROPERTY(bool peekFavorited READ peekFavorited NOTIFY peekChanged)
    Q_PROPERTY(double peekAspect READ peekAspect NOTIFY peekChanged)
    Q_PROPERTY(bool personalEmpty READ personalEmpty NOTIFY statusChanged)
    Q_PROPERTY(QStringList selectedTags READ selectedTags NOTIFY tagsChanged)
    Q_PROPERTY(QString selectedSummary READ selectedSummary NOTIFY tagsChanged)
    Q_PROPERTY(QString tagInput READ tagInput WRITE setTagInput NOTIFY tagInputChanged)
    Q_PROPERTY(QString poolQuery READ poolQuery WRITE setPoolQuery NOTIFY poolQueryChanged)
    Q_PROPERTY(QString addHost READ addHost WRITE setAddHost NOTIFY addHostChanged)
    Q_PROPERTY(QString addStatus READ addStatus NOTIFY addStatusChanged)
    Q_PROPERTY(QString downloadFolder READ downloadFolder WRITE setDownloadFolder NOTIFY settingsChanged)
    Q_PROPERTY(bool askDownloadFolder READ askDownloadFolder WRITE setAskDownloadFolder NOTIFY settingsChanged)
    Q_PROPERTY(QString favoriteFolderId READ favoriteFolderId WRITE setFavoriteFolderId NOTIFY favoriteFolderChanged)
    Q_PROPERTY(QString lastFavoriteFolderId READ lastFavoriteFolderId NOTIFY favoriteFolderChanged)
    Q_PROPERTY(double layoutHeight READ layoutHeight NOTIFY layoutChanged)
    Q_PROPERTY(double layoutColumnWidth READ layoutColumnWidth NOTIFY layoutChanged)
    Q_PROPERTY(int layoutColumns READ layoutColumns NOTIFY layoutChanged)
    Q_PROPERTY(PostListModel *posts READ posts CONSTANT)
    Q_PROPERTY(TagListModel *pageTags READ pageTags CONSTANT)
    Q_PROPERTY(TagListModel *suggestions READ suggestions CONSTANT)
    Q_PROPERTY(TagListModel *viewerTags READ viewerTags CONSTANT)
    Q_PROPERTY(TagListModel *peekTags READ peekTags CONSTANT)
    Q_PROPERTY(ServerListModel *servers READ servers CONSTANT)
    Q_PROPERTY(PoolListModel *pools READ pools CONSTANT)
    Q_PROPERTY(SavedSetListModel *savedSets READ savedSets CONSTANT)
    Q_PROPERTY(FolderListModel *folders READ folders CONSTANT)
    Q_PROPERTY(SelectionStore *selectedPosts READ selectedPosts CONSTANT)
    Q_PROPERTY(DownloadStore *downloads READ downloads CONSTANT)
    Q_PROPERTY(QVariantList pageTagGroups READ pageTagGroups NOTIFY pageTagsChanged)
    Q_PROPERTY(QVariantList peekTagGroups READ peekTagGroups NOTIFY peekChanged)
    Q_PROPERTY(QStringList serverPalette READ serverPalette CONSTANT)

public:
    enum Tab { Feed = 0, Browse, Pools, Favorites, Settings };
    Q_ENUM(Tab)

    explicit AppController(QObject *parent = nullptr);

    int tab() const { return int(m_tab); }
    void setTab(int tab);
    bool compact() const { return m_width < 700; }
    double windowWidth() const { return m_width; }
    void setWindowWidth(double width);
    bool loading() const { return m_loading; }
    QString statusText() const { return m_status; }
    QString errorText() const { return m_error; }
    int feedChannel() const { return int(m_channel); }
    void setFeedChannel(int channel);
    int ratingFilter() const;
    void setRatingFilter(int filter);
    int tilingMode() const;
    void setTilingMode(int mode);
    int tileExtent() const;
    void setTileExtent(int extent);
    bool loadFullQuality() const;
    void setLoadFullQuality(bool enabled);
    bool showsSidebar() const;
    void setShowsSidebar(bool visible);
    bool browseOnSidebar() const { return m_browseOnSidebar; }
    void setBrowseOnSidebar(bool on);
    bool favoritesOnSidebar() const { return m_favoritesOnSidebar; }
    void setFavoritesOnSidebar(bool on);
    bool poolDetail() const { return m_poolDetail; }
    QString poolTitle() const;
    double scrollOffset() const { return m_scrollOffset; }
    void setScrollOffset(double offset);
    int preferredTileWidth() const;
    bool viewerOpen() const { return m_viewerOpen; }
    int viewerIndex() const { return m_viewerIndex; }
    QString viewerUrl() const;
    QString viewerMeta() const;
    bool viewerFavorited() const;
    bool viewerHasOriginal() const;
    double viewerProgress() const { return m_viewerProgress; }
    bool peekOpen() const { return m_peekOpen; }
    QString peekUrl() const;
    QString peekMeta() const;
    bool peekFavorited() const;
    double peekAspect() const;
    bool personalEmpty() const;
    QStringList selectedTags() const { return m_selectedTags; }
    QString selectedSummary() const { return m_selectedTags.join(QLatin1Char(' ')); }
    QString tagInput() const { return m_tagInput; }
    void setTagInput(const QString &text);
    QString poolQuery() const { return m_poolQuery; }
    void setPoolQuery(const QString &text);
    QString addHost() const { return m_addHost; }
    void setAddHost(const QString &host);
    QString addStatus() const { return m_addStatus; }
    QString downloadFolder() const;
    void setDownloadFolder(const QString &path);
    bool askDownloadFolder() const;
    void setAskDownloadFolder(bool ask);
    QString favoriteFolderId() const { return m_favoriteFolderId; }
    void setFavoriteFolderId(const QString &id);
    QString lastFavoriteFolderId() const;
    double layoutHeight() const { return m_layout.contentHeight; }
    double layoutColumnWidth() const { return m_layout.columnWidth; }
    int layoutColumns() const { return m_layout.columns; }

    PostListModel *posts() const { return m_posts; }
    TagListModel *pageTags() const { return m_pageTags; }
    TagListModel *suggestions() const { return m_suggestions; }
    TagListModel *viewerTags() const { return m_viewerTags; }
    TagListModel *peekTags() const { return m_peekTags; }
    ServerListModel *servers() const { return m_servers; }
    PoolListModel *pools() const { return m_poolsModel; }
    SavedSetListModel *savedSets() const { return m_savedSets; }
    FolderListModel *folders() const { return m_folders; }
    SelectionStore *selectedPosts() const;
    DownloadStore *downloads() const;
    QVariantList pageTagGroups() const { return m_pageTagGroups; }
    QVariantList peekTagGroups() const { return m_peekTagGroups; }
    QStringList serverPalette() const;

    Q_INVOKABLE void reload();
    Q_INVOKABLE void loadMore();
    Q_INVOKABLE void addTag(const QString &tag);
    Q_INVOKABLE void toggleTag(const QString &tag);
    Q_INVOKABLE void removeTag(const QString &tag);
    Q_INVOKABLE bool hasTag(const QString &tag) const;
    Q_INVOKABLE void clearTags();
    Q_INVOKABLE void commitTagInput();
    Q_INVOKABLE void saveCurrentSet(const QString &name, bool addToPersonal);
    Q_INVOKABLE void applySavedSet(int index);
    Q_INVOKABLE void deleteSavedSet(int index);
    Q_INVOKABLE void togglePersonalSet(int index, bool enabled);
    Q_INVOKABLE void openViewer(int index);
    Q_INVOKABLE void closeViewer();
    Q_INVOKABLE void viewerMove(int delta);
    Q_INVOKABLE void toggleFavoriteAt(int index);
    Q_INVOKABLE void toggleViewerFavorite();
    Q_INVOKABLE void loadViewerOriginal();
    Q_INVOKABLE void openViewerSite();
    Q_INVOKABLE void openViewerSource();
    Q_INVOKABLE void saveViewerFile(const QString &path);
    Q_INVOKABLE void openPool(int index);
    Q_INVOKABLE void leavePool();
    Q_INVOKABLE void searchPools();
    Q_INVOKABLE QString tagColor(const QString &name) const;
    Q_INVOKABLE void setServerEnabled(int index, bool enabled);
    Q_INVOKABLE void setServerCredentials(int index, const QString &user, const QString &key);
    Q_INVOKABLE void setServerColor(int index, const QString &hex);
    Q_INVOKABLE void addServer();
    Q_INVOKABLE void removeServer(int index);
    Q_INVOKABLE QString suggestedSaveName() const;
    Q_INVOKABLE int gridColumns(double width) const;
    Q_INVOKABLE void prepareLayout(double innerWidth);
    Q_INVOKABLE double itemX(int index) const;
    Q_INVOKABLE double itemY(int index) const;
    Q_INVOKABLE double itemH(int index) const;
    /// Post indices whose layout frames intersect [top, bottom] (content coordinates).
    Q_INVOKABLE QVariantList indexesInYRange(double top, double bottom) const;
    Q_INVOKABLE void toggleSelectedAt(int index);
    Q_INVOKABLE void openPeek(int index);
    Q_INVOKABLE void closePeek();
    Q_INVOKABLE void peekSelect();
    Q_INVOKABLE void peekFavorite();
    Q_INVOKABLE void openPeekSite();
    Q_INVOKABLE void savePeekFile(const QString &path);
    Q_INVOKABLE QString suggestedPeekName() const;
    Q_INVOKABLE void requestFavoriteSelected();
    Q_INVOKABLE void confirmFavorite(const QString &folderId);
    Q_INVOKABLE void confirmFavoriteNew(const QString &name);
    Q_INVOKABLE void enqueueDownloads(const QString &folder);
    Q_INVOKABLE void createFavoriteFolder(const QString &name);
    Q_INVOKABLE void renameFavoriteFolder(const QString &id, const QString &name);
    Q_INVOKABLE void deleteFavoriteFolder(const QString &id, bool deletePosts);

signals:
    void tabChanged();
    void compactChanged();
    void loadingChanged();
    void statusChanged();
    void feedChannelChanged();
    void settingsChanged();
    void browseColumnChanged();
    void poolDetailChanged();
    void scrollOffsetChanged();
    void viewerChanged();
    void viewerProgressChanged();
    void peekChanged();
    void tagsChanged();
    void tagInputChanged();
    void poolQueryChanged();
    void addHostChanged();
    void addStatusChanged();
    void pageTagsChanged();
    void layoutChanged();
    void favoriteFolderChanged();
    void favoriteDialogRequested();

private:
    enum Section { SecFeed, SecBrowse, SecPools, SecFavorites };

    struct Session {
        QVector<BooruPost> posts;
        QString fingerprint;
        bool poolDetail = false;
        BooruPool pool;
        double scroll = 0;
    };

    void reloadCurrent();
    void reloadFeed();
    void reloadBrowse();
    void reloadFavorites();
    void reloadPools();
    void handlePage(FeedAggregator *source, const QVector<BooruPost> &posts, const QString &error);
    void showPosts(const QVector<BooruPost> &posts, bool append);
    void refreshPageTags();
    void refreshViewer();
    void refreshPeek();
    void syncTagSelectionViews();
    void stash();
    void restoreOrReload();
    QString fingerprint() const;
    GallerySection gallerySection() const;
    RatingFilter filter() const;
    FeedAggregator *activeAggregator() const;
    QVector<BooruServer> poolServers() const;
    void requestPoolPreviews(const QVector<BooruPool> &pools, int startRow);
    void rebuildLayout();
    void requestFavoritePosts(const QVector<BooruPost> &posts);
    QString saveNameFor(const BooruPost &post) const;

    Tab m_tab = Browse;
    Tab m_lastTab = Browse;
    double m_width = 1100;
    double m_layoutWidth = 0;
    bool m_loading = false;
    bool m_browseOnSidebar = false;
    bool m_favoritesOnSidebar = false;
    bool m_viewerOpen = false;
    bool m_viewerUseOriginal = false;
    bool m_peekOpen = false;
    bool m_poolDetail = false;
    bool m_refreshingFavorites = false;
    bool m_pendingFromSelection = false;
    int m_viewerIndex = 0;
    int m_peekIndex = -1;
    double m_scrollOffset = 0;
    double m_viewerProgress = 0;
    int m_viewerGeneration = 0;
    FeedChannel m_channel = FeedChannel::Personal;
    QString m_status = QStringLiteral("Ready");
    QString m_error;
    QStringList m_selectedTags;
    QString m_tagInput;
    QString m_poolQuery;
    QString m_addHost;
    QString m_addStatus;
    QString m_favoriteFolderId;
    QVector<BooruPost> m_currentPosts;
    QVector<BooruPost> m_pendingFavorites;
    Session m_sessions[4];
    BooruPool m_openPool;
    GalleryLayoutResult m_layout;

    FeedAggregator *m_browseAgg = nullptr;
    FeedAggregator *m_feedAgg = nullptr;
    FeedAggregator *m_poolAgg = nullptr;
    PoolAggregator *m_poolListAgg = nullptr;
    PostListModel *m_posts = nullptr;
    TagListModel *m_pageTags = nullptr;
    TagListModel *m_suggestions = nullptr;
    TagListModel *m_viewerTags = nullptr;
    TagListModel *m_peekTags = nullptr;
    ServerListModel *m_servers = nullptr;
    PoolListModel *m_poolsModel = nullptr;
    SavedSetListModel *m_savedSets = nullptr;
    FolderListModel *m_folders = nullptr;
    QVariantList m_pageTagGroups;
    QVariantList m_peekTagGroups;
};
