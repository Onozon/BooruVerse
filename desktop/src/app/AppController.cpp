#include "app/AppController.h"

#include "api/BooruClient.h"
#include "api/FeedAggregator.h"
#include "api/PoolAggregator.h"
#include "api/ServerProbe.h"
#include "app/PostListModel.h"
#include "app/SimpleListModels.h"
#include "app/ThumbImageProvider.h"
#include "core/DownloadStore.h"
#include "core/FavoriteStore.h"
#include "core/GalleryLayout.h"
#include "core/GallerySettings.h"
#include "core/HttpClient.h"
#include "core/PersonalFeedStore.h"
#include "core/SavedTagSetStore.h"
#include "core/SelectionStore.h"
#include "core/ServerStore.h"
#include "core/TagIndexStore.h"

#include <QDesktopServices>
#include <QFile>
#include <QSettings>
#include <QTimer>
#include <QUrl>
#include <QVariantMap>

#include <algorithm>

static QString localFolderPath(const QString &raw) {
    const QString trimmed = raw.trimmed();
    if (trimmed.startsWith(QLatin1String("file:")))
        return QUrl(trimmed).toLocalFile();
    return trimmed;
}

static int sessionIndex(AppController::Tab tab) {
    switch (tab) {
    case AppController::Feed:
        return 0;
    case AppController::Browse:
        return 1;
    case AppController::Pools:
        return 2;
    case AppController::Favorites:
        return 3;
    case AppController::Settings:
        return -1;
    }
    return -1;
}

AppController::AppController(QObject *parent)
    : QObject(parent)
    , m_browseAgg(new FeedAggregator(this))
    , m_feedAgg(new FeedAggregator(this))
    , m_poolAgg(new FeedAggregator(this))
    , m_poolListAgg(new PoolAggregator(this))
    , m_posts(new PostListModel(this))
    , m_pageTags(new TagListModel(this))
    , m_suggestions(new TagListModel(this))
    , m_viewerTags(new TagListModel(this))
    , m_peekTags(new TagListModel(this))
    , m_servers(new ServerListModel(this))
    , m_poolsModel(new PoolListModel(this))
    , m_savedSets(new SavedSetListModel(this))
    , m_folders(new FolderListModel(this)) {
    m_channel = FeedChannel(QSettings().value(QStringLiteral("feed/channel"), 0).toInt());
    m_favoriteFolderId = FavoriteStore::instance().lastFolderId();

    auto bind = [this](FeedAggregator *aggregator) {
        connect(aggregator, &FeedAggregator::pageReady, this,
                [this, aggregator](const QVector<BooruPost> &posts, const QString &error) {
                    handlePage(aggregator, posts, error);
                });
        connect(aggregator, &FeedAggregator::loadingChanged, this, [this, aggregator](bool loading) {
            if (activeAggregator() != aggregator)
                return;
            m_loading = loading;
            emit loadingChanged();
            if (loading) {
                m_status = QStringLiteral("Loading…");
                emit statusChanged();
            }
        });
    };
    bind(m_browseAgg);
    bind(m_feedAgg);
    bind(m_poolAgg);

    connect(m_poolListAgg, &PoolAggregator::loadingChanged, this, [this](bool loading) {
        if (m_tab != Pools || m_poolDetail)
            return;
        m_loading = loading;
        emit loadingChanged();
    });
    connect(m_poolListAgg, &PoolAggregator::pageReady, this, [this](const QVector<BooruPool> &pools, const QString &error) {
        const int start = m_poolsModel->rowCount();
        m_poolsModel->appendPools(pools);
        requestPoolPreviews(pools, start);
        m_error = error;
        if (m_tab == Pools && !m_poolDetail) {
            m_status = QStringLiteral("Pools");
            emit statusChanged();
        }
    });
    connect(&ServerStore::instance(), &ServerStore::changed, this, [this]() {
        m_servers->reload();
        emit settingsChanged();
        for (Session &session : m_sessions)
            session.fingerprint.clear();
        if (m_tab != Settings)
            reloadCurrent();
    });
    connect(&FavoriteStore::instance(), &FavoriteStore::changed, this, [this]() {
        m_posts->refreshFavorites();
        m_folders->reload();
        emit viewerChanged();
        emit peekChanged();
        emit favoriteFolderChanged();
        if (m_tab == Favorites && !m_refreshingFavorites)
            reloadFavorites();
    });
    connect(&SelectionStore::instance(), &SelectionStore::countChanged, this, [this]() {
        m_posts->refreshSelection();
    });
    connect(&SavedTagSetStore::instance(), &SavedTagSetStore::changed, this, [this]() {
        m_savedSets->reload();
        if (m_tab == Feed && m_channel == FeedChannel::Personal)
            reloadFeed();
    });
    connect(&PersonalFeedStore::instance(), &PersonalFeedStore::changed, this, [this]() {
        m_savedSets->reload();
        if (m_tab == Feed && m_channel == FeedChannel::Personal)
            reloadFeed();
    });
    connect(&TagIndexStore::instance(), &TagIndexStore::changed, this, [this]() {
        refreshPageTags();
        refreshViewer();
        refreshPeek();
    });
    connect(&GallerySettings::instance(), &GallerySettings::changed, this, [this]() {
        emit settingsChanged();
        rebuildLayout();
    });

    auto *suggestTimer = new QTimer(this);
    suggestTimer->setSingleShot(true);
    suggestTimer->setInterval(220);
    connect(this, &AppController::tagInputChanged, this, [this, suggestTimer]() {
        suggestTimer->start();
    });
    connect(suggestTimer, &QTimer::timeout, this, [this]() {
        const QString fragment = m_tagInput.trimmed();
        if (fragment.size() < 2) {
            m_suggestions->setTags({});
            return;
        }
        BooruClient::suggestFromServers(ServerStore::instance().enabledServers(), m_selectedTags, fragment,
                                        [this, fragment](QVector<BooruTag> tags, QString) {
                                            if (m_tagInput.trimmed() != fragment)
                                                return;
                                            m_suggestions->setTags(tags, m_selectedTags);
                                        });
    });

    reloadBrowse();
}

void AppController::setTab(int tab) {
    const auto next = Tab(qBound(0, tab, 4));
    if (next == m_tab)
        return;
    if (m_tab != Settings)
        stash();
    m_tab = next;
    // Drop decoded thumbnails when leaving a gallery tab so inactive stacks
    // do not keep hundreds of bitmaps resident (matches Apple purgeDecodedImages intent).
    ThumbImageProvider::purgeCache();
    emit tabChanged();
    emit settingsChanged();
    if (m_tab != Settings) {
        restoreOrReload();
        m_lastTab = m_tab;
    }
}

void AppController::setWindowWidth(double width) {
    const bool wasCompact = compact();
    m_width = width;
    if (wasCompact != compact()) {
        if (!compact())
            m_browseOnSidebar = false;
        emit compactChanged();
        emit browseColumnChanged();
        emit settingsChanged();
    }
}

void AppController::setFeedChannel(int channel) {
    const auto next = FeedChannel(qBound(0, channel, 3));
    if (next == m_channel)
        return;
    m_channel = next;
    QSettings().setValue(QStringLiteral("feed/channel"), int(m_channel));
    m_sessions[SecFeed].fingerprint.clear();
    emit feedChannelChanged();
    if (m_tab == Feed)
        reloadFeed();
}

int AppController::ratingFilter() const {
    return int(GallerySettings::instance().ratingFilter());
}

void AppController::setRatingFilter(int filter) {
    GallerySettings::instance().setRatingFilter(RatingFilter(filter));
    for (Session &session : m_sessions)
        session.fingerprint.clear();
    if (m_tab != Settings)
        reloadCurrent();
}

int AppController::tilingMode() const {
    return int(GallerySettings::instance().tilingMode());
}

void AppController::setTilingMode(int mode) {
    GallerySettings::instance().setTilingMode(TilingMode(mode));
}

int AppController::tileExtent() const {
    return GallerySettings::instance().tileExtent(gallerySection());
}

void AppController::setTileExtent(int extent) {
    GallerySettings::instance().setTileExtent(gallerySection(), extent);
}

bool AppController::loadFullQuality() const {
    return GallerySettings::instance().loadFullQuality();
}

void AppController::setLoadFullQuality(bool enabled) {
    GallerySettings::instance().setLoadFullQuality(enabled);
    emit viewerChanged();
}

bool AppController::showsSidebar() const {
    return GallerySettings::instance().showsSidebar();
}

void AppController::setShowsSidebar(bool visible) {
    GallerySettings::instance().setShowsSidebar(visible);
}

void AppController::setFavoritesOnSidebar(bool on) {
    if (m_favoritesOnSidebar == on)
        return;
    m_favoritesOnSidebar = on;
    emit browseColumnChanged();
}

void AppController::setBrowseOnSidebar(bool on) {
    if (m_browseOnSidebar == on)
        return;
    m_browseOnSidebar = on;
    emit browseColumnChanged();
}

QString AppController::poolTitle() const {
    return m_poolDetail ? m_openPool.displayName() : QStringLiteral("Pools");
}

void AppController::setScrollOffset(double offset) {
    if (qFuzzyCompare(m_scrollOffset, offset))
        return;
    m_scrollOffset = offset;
    emit scrollOffsetChanged();
}

int AppController::preferredTileWidth() const {
    return GallerySettings::instance().preferredTileWidth(gallerySection());
}

void AppController::setTagInput(const QString &text) {
    if (m_tagInput == text)
        return;
    m_tagInput = text;
    emit tagInputChanged();
}

void AppController::setPoolQuery(const QString &text) {
    if (m_poolQuery == text)
        return;
    m_poolQuery = text;
    emit poolQueryChanged();
}

void AppController::setAddHost(const QString &host) {
    if (m_addHost == host)
        return;
    m_addHost = host;
    emit addHostChanged();
}

bool AppController::personalEmpty() const {
    return m_tab == Feed && m_channel == FeedChannel::Personal
        && PersonalFeedStore::instance().personalSets().isEmpty();
}

QString AppController::viewerUrl() const {
    if (m_viewerIndex < 0 || m_viewerIndex >= m_currentPosts.size())
        return {};
    const BooruPost &post = m_currentPosts[m_viewerIndex];
    if ((m_viewerUseOriginal || GallerySettings::instance().loadFullQuality()) && !post.fileUrl.isEmpty())
        return post.fileUrl.toString();
    return post.viewerUrl().toString();
}

QString AppController::viewerMeta() const {
    if (m_viewerIndex < 0 || m_viewerIndex >= m_currentPosts.size())
        return {};
    const BooruPost &post = m_currentPosts[m_viewerIndex];
    return QStringLiteral("%1  #%2  %3×%4  %5 / %6")
        .arg(post.serverId)
        .arg(post.id)
        .arg(post.width)
        .arg(post.height)
        .arg(m_viewerIndex + 1)
        .arg(m_currentPosts.size());
}

bool AppController::viewerFavorited() const {
    if (m_viewerIndex < 0 || m_viewerIndex >= m_currentPosts.size())
        return false;
    return FavoriteStore::instance().contains(m_currentPosts[m_viewerIndex].globalId());
}

bool AppController::viewerHasOriginal() const {
    if (m_viewerIndex < 0 || m_viewerIndex >= m_currentPosts.size())
        return false;
    return m_currentPosts[m_viewerIndex].hasHigherQualityOriginal();
}

void AppController::reload() {
    const int index = sessionIndex(m_tab);
    if (index >= 0)
        m_sessions[index].fingerprint.clear();
    reloadCurrent();
}

void AppController::loadMore() {
    if (m_loading)
        return;
    if (FeedAggregator *aggregator = activeAggregator())
        aggregator->loadMore();
    else if (m_tab == Pools && !m_poolDetail)
        m_poolListAgg->loadMore();
}

void AppController::addTag(const QString &tag) {
    const QString normalized = tag.trimmed().toLower();
    if (normalized.isEmpty() || m_selectedTags.contains(normalized))
        return;
    if (m_tab != Browse)
        setTab(Browse);
    m_selectedTags.append(normalized);
    m_tagInput.clear();
    m_suggestions->setTags({});
    emit tagInputChanged();
    emit tagsChanged();
    syncTagSelectionViews();
    m_sessions[SecBrowse].fingerprint.clear();
    if (!compact())
        m_browseOnSidebar = false;
    reloadBrowse();
}

void AppController::toggleTag(const QString &tag) {
    const QString normalized = tag.trimmed().toLower();
    if (normalized.isEmpty())
        return;
    if (m_selectedTags.contains(normalized))
        m_selectedTags.removeAll(normalized);
    else
        m_selectedTags.append(normalized);
    m_tagInput.clear();
    m_suggestions->setTags({});
    emit tagInputChanged();
    emit tagsChanged();
    syncTagSelectionViews();
    m_sessions[SecBrowse].fingerprint.clear();
    if (m_tab == Browse)
        reloadBrowse();
}

bool AppController::hasTag(const QString &tag) const {
    return m_selectedTags.contains(tag.trimmed().toLower());
}

void AppController::removeTag(const QString &tag) {
    m_selectedTags.removeAll(tag.trimmed().toLower());
    emit tagsChanged();
    syncTagSelectionViews();
    m_sessions[SecBrowse].fingerprint.clear();
    if (m_tab == Browse)
        reloadBrowse();
}

void AppController::clearTags() {
    if (m_selectedTags.isEmpty())
        return;
    m_selectedTags.clear();
    emit tagsChanged();
    syncTagSelectionViews();
    m_sessions[SecBrowse].fingerprint.clear();
    if (m_tab == Browse)
        reloadBrowse();
}

void AppController::commitTagInput() {
    addTag(m_tagInput);
}

void AppController::saveCurrentSet(const QString &name, bool addToPersonal) {
    SavedTagSetStore::instance().save(name, m_selectedTags, addToPersonal);
}

void AppController::applySavedSet(int index) {
    const SavedTagSet set = m_savedSets->at(index);
    if (set.tags.isEmpty())
        return;
    m_selectedTags = set.tags;
    emit tagsChanged();
    setTab(Browse);
    m_sessions[SecBrowse].fingerprint.clear();
    reloadBrowse();
}

void AppController::deleteSavedSet(int index) {
    SavedTagSetStore::instance().remove(m_savedSets->at(index).id);
}

void AppController::togglePersonalSet(int index, bool enabled) {
    PersonalFeedStore::instance().setEnabled(m_savedSets->at(index).id, enabled);
}

void AppController::openViewer(int index) {
    if (index < 0 || index >= m_currentPosts.size())
        return;
    m_viewerOpen = true;
    m_viewerIndex = index;
    m_viewerUseOriginal = GallerySettings::instance().loadFullQuality();
    refreshViewer();
    emit viewerChanged();
}

void AppController::closeViewer() {
    m_viewerOpen = false;
    emit viewerChanged();
}

void AppController::viewerMove(int delta) {
    if (m_currentPosts.isEmpty())
        return;
    m_viewerIndex = qBound(0, m_viewerIndex + delta, m_currentPosts.size() - 1);
    m_viewerUseOriginal = GallerySettings::instance().loadFullQuality();
    refreshViewer();
    emit viewerChanged();
    if (m_viewerIndex >= m_currentPosts.size() - 20)
        loadMore();
}

void AppController::toggleFavoriteAt(int index) {
    if (index < 0 || index >= m_currentPosts.size())
        return;
    const BooruPost &post = m_currentPosts[index];
    if (FavoriteStore::instance().contains(post.globalId()))
        FavoriteStore::instance().unfavorite(post.globalId());
    else
        requestFavoritePosts({post});
}

void AppController::toggleViewerFavorite() {
    if (m_viewerIndex < 0 || m_viewerIndex >= m_currentPosts.size())
        return;
    const BooruPost &post = m_currentPosts[m_viewerIndex];
    if (FavoriteStore::instance().contains(post.globalId()))
        FavoriteStore::instance().unfavorite(post.globalId());
    else
        requestFavoritePosts({post});
}

void AppController::loadViewerOriginal() {
    if (m_viewerIndex < 0 || m_viewerIndex >= m_currentPosts.size())
        return;
    m_viewerUseOriginal = true;
    emit viewerChanged();
}

void AppController::openViewerSite() {
    if (m_viewerIndex < 0 || m_viewerIndex >= m_currentPosts.size())
        return;
    const BooruPost &post = m_currentPosts[m_viewerIndex];
    QDesktopServices::openUrl(postPageUrl(post, ServerStore::instance().serverFor(post.serverId).flavor));
}

void AppController::openViewerSource() {
    if (m_viewerIndex < 0 || m_viewerIndex >= m_currentPosts.size())
        return;
    const QUrl source = m_currentPosts[m_viewerIndex].sourceUrl;
    if (!source.isEmpty())
        QDesktopServices::openUrl(source);
}

void AppController::saveViewerFile(const QString &path) {
    const QString dest = localFolderPath(path);
    if (dest.isEmpty() || m_viewerIndex < 0 || m_viewerIndex >= m_currentPosts.size())
        return;
    const BooruPost &post = m_currentPosts[m_viewerIndex];
    const QUrl url = post.fileUrl.isEmpty() ? post.viewerUrl() : post.fileUrl;
    HttpClient::instance().get(url, {}, [dest](QByteArray data, QString) {
        QFile file(dest);
        if (file.open(QIODevice::WriteOnly))
            file.write(data);
    });
}

void AppController::openPool(int index) {
    const BooruPool pool = m_poolsModel->at(index);
    if (pool.id <= 0)
        return;
    m_poolDetail = true;
    m_openPool = pool;
    m_currentPosts.clear();
    m_posts->clear();
    m_loading = true;
    emit loadingChanged();
    m_poolAgg->loadPool(ServerStore::instance().serverFor(pool.serverId), pool.id, filter());
    m_sessions[SecPools].fingerprint = fingerprint();
    m_status = pool.displayName();
    emit statusChanged();
    emit poolDetailChanged();
}

void AppController::leavePool() {
    if (!m_poolDetail)
        return;
    m_poolDetail = false;
    m_currentPosts.clear();
    m_posts->clear();
    m_sessions[SecPools].fingerprint = fingerprint();
    m_sessions[SecPools].poolDetail = false;
    m_status = QStringLiteral("Pools");
    emit statusChanged();
    emit poolDetailChanged();
}

void AppController::searchPools() {
    m_poolDetail = false;
    m_sessions[SecPools].fingerprint.clear();
    emit poolDetailChanged();
    reloadPools();
}

QString AppController::tagColor(const QString &name) const {
    return tagTypeColor(TagIndexStore::instance().typeFor(name)).name();
}

void AppController::setServerEnabled(int index, bool enabled) {
    const BooruServer server = m_servers->at(index);
    if (!server.host.isEmpty())
        ServerStore::instance().setEnabled(server.host, enabled);
}

void AppController::setServerCredentials(int index, const QString &user, const QString &key) {
    const BooruServer server = m_servers->at(index);
    if (!server.host.isEmpty())
        ServerStore::instance().setCredentials(server.host, user, key);
}

void AppController::setServerColor(int index, const QString &hex) {
    const BooruServer server = m_servers->at(index);
    if (!server.host.isEmpty())
        ServerStore::instance().setColor(server.host, hex);
}

void AppController::addServer() {
    const QString host = m_addHost.trimmed();
    if (host.isEmpty()) {
        m_addStatus = QStringLiteral("Enter a host.");
        emit addStatusChanged();
        return;
    }
    m_addStatus = QStringLiteral("Detecting API…");
    emit addStatusChanged();
    ServerProbe::detect(host, [this, host](bool ok, ApiFlavor flavor, QString error) {
        if (!ok) {
            m_addStatus = error;
            emit addStatusChanged();
            return;
        }
        const QString normalized = ServerProbe::normalizeHost(host);
        ServerStore::instance().addCustom(normalized, flavor);
        m_addHost.clear();
        m_addStatus = QStringLiteral("Added %1 as %2.").arg(normalized, flavorTitle(flavor));
        emit addHostChanged();
        emit addStatusChanged();
    });
}

void AppController::removeServer(int index) {
    const BooruServer server = m_servers->at(index);
    if (!server.builtIn)
        ServerStore::instance().removeHost(server.host);
}

int AppController::gridColumns(double width) const {
    const int tile = qMax(GallerySettings::instance().preferredTileWidth(gallerySection()), 1);
    const int maxCols = compact() ? 3 : 10;
    constexpr double spacing = 10;
    if (width <= 0)
        return 1;
    return qBound(1, int((width + spacing) / (tile + spacing)), maxCols);
}

void AppController::reloadCurrent() {
    switch (m_tab) {
    case Feed:
        reloadFeed();
        break;
    case Browse:
        reloadBrowse();
        break;
    case Pools:
        reloadPools();
        break;
    case Favorites:
        reloadFavorites();
        break;
    case Settings:
        break;
    }
}

void AppController::reloadFeed() {
    m_poolDetail = false;
    m_currentPosts.clear();
    m_posts->clear();
    if (m_channel == FeedChannel::Personal) {
        QVector<QStringList> tagSets;
        for (const SavedTagSet &set : PersonalFeedStore::instance().personalSets())
            tagSets.append(set.tags);
        if (tagSets.isEmpty()) {
            m_loading = false;
            m_status = QStringLiteral("Save a tag set and add it to Personal feed");
            emit loadingChanged();
            emit statusChanged();
            m_sessions[SecFeed].fingerprint = fingerprint();
            return;
        }
        m_feedAgg->loadPersonal(ServerStore::instance().enabledServers(), tagSets, filter());
    } else {
        m_feedAgg->loadPopular(ServerStore::instance().enabledServers(), PopularPeriod(int(m_channel) - 1),
                               filter());
    }
    m_sessions[SecFeed].fingerprint = fingerprint();
}

void AppController::reloadBrowse() {
    m_poolDetail = false;
    m_currentPosts.clear();
    m_posts->clear();
    m_pageTags->setTags({});
    m_browseAgg->reset(ServerStore::instance().enabledServers(), m_selectedTags.join(QLatin1Char(' ')), filter());
    m_sessions[SecBrowse].fingerprint = fingerprint();
}

void AppController::reloadFavorites() {
    m_poolDetail = false;
    QVector<BooruPost> posts;
    for (const BooruPost &post : FavoriteStore::instance().postsInFolder(m_favoriteFolderId)) {
        if (post.allowedBy(filter()))
            posts.append(post);
    }
    showPosts(posts, false);
    m_sessions[SecFavorites].posts = posts;
    m_sessions[SecFavorites].fingerprint = fingerprint();
    m_status = QStringLiteral("%1 favorites").arg(posts.size());
    emit statusChanged();

    if (m_refreshingFavorites)
        return;
    m_refreshingFavorites = true;
    auto *pending = new int(0);
    for (const BooruPost &post : FavoriteStore::instance().posts()) {
        const BooruServer server = ServerStore::instance().serverFor(post.serverId);
        if (server.host.isEmpty())
            continue;
        ++*pending;
        BooruClient::fetchPost(server, post.id, [this, pending](QVector<BooruPost> fresh, QString) {
            if (!fresh.isEmpty())
                FavoriteStore::instance().updateSnapshot(fresh.first());
            if (--*pending > 0)
                return;
            delete pending;
            m_refreshingFavorites = false;
            if (m_tab == Favorites) {
                QVector<BooruPost> posts;
                for (const BooruPost &updated : FavoriteStore::instance().postsInFolder(m_favoriteFolderId)) {
                    if (updated.allowedBy(filter()))
                        posts.append(updated);
                }
                showPosts(posts, false);
                m_sessions[SecFavorites].posts = posts;
            }
        });
    }
    if (*pending == 0) {
        delete pending;
        m_refreshingFavorites = false;
    }
}

void AppController::reloadPools() {
    m_poolDetail = false;
    m_currentPosts.clear();
    m_posts->clear();
    m_poolsModel->clear();
    const QVector<BooruServer> servers = poolServers();
    if (servers.isEmpty()) {
        m_status = QStringLiteral("Enable yande.re or konachan.com in Settings");
        emit statusChanged();
        return;
    }
    m_status = QStringLiteral("Loading pools…");
    emit statusChanged();
    m_poolListAgg->reset(servers, m_poolQuery);
    m_sessions[SecPools].fingerprint = fingerprint();
}

void AppController::handlePage(FeedAggregator *source, const QVector<BooruPost> &posts, const QString &error) {
    int owner = -1;
    if (source == m_feedAgg)
        owner = SecFeed;
    else if (source == m_browseAgg)
        owner = SecBrowse;
    else
        owner = SecPools;

    const int current = sessionIndex(m_tab);
    if (current != owner) {
        m_sessions[owner].posts += posts;
        return;
    }
    showPosts(posts, !m_currentPosts.isEmpty());
    m_sessions[owner].posts = m_currentPosts;
    m_error = error;
    m_status = QStringLiteral("%1 posts").arg(m_currentPosts.size());
    emit statusChanged();
    if (m_tab == Browse)
        refreshPageTags();
    if (m_viewerOpen)
        emit viewerChanged();
}

void AppController::showPosts(const QVector<BooruPost> &posts, bool append) {
    if (append) {
        m_currentPosts += posts;
        m_posts->appendPosts(posts);
    } else {
        m_currentPosts = posts;
        m_posts->setPosts(posts);
    }
    rebuildLayout();
}

void AppController::refreshPageTags() {
    const int start = qMax(0, m_currentPosts.size() - 40);
    QHash<QString, int> counts;
    QStringList names;
    for (int i = start; i < m_currentPosts.size(); ++i) {
        for (const QString &tag : m_currentPosts[i].tags) {
            if (tag.isEmpty())
                continue;
            counts[tag] += 1;
            if (!names.contains(tag))
                names.append(tag);
        }
    }
    QVector<BooruTag> tags;
    for (auto it = counts.cbegin(); it != counts.cend(); ++it) {
        BooruTag tag;
        tag.name = it.key();
        tag.postCount = it.value();
        tag.type = TagIndexStore::instance().typeFor(tag.name);
        tags.append(tag);
    }
    auto typeOrder = [](TagType type) {
        switch (type) {
        case TagType::Copyright:
            return 0;
        case TagType::Character:
            return 1;
        case TagType::Artist:
            return 2;
        case TagType::General:
            return 3;
        case TagType::Meta:
            return 4;
        }
        return 3;
    };
    std::sort(tags.begin(), tags.end(), [&](const BooruTag &a, const BooruTag &b) {
        if (typeOrder(a.type) != typeOrder(b.type))
            return typeOrder(a.type) < typeOrder(b.type);
        if (a.postCount != b.postCount)
            return a.postCount > b.postCount;
        return a.name < b.name;
    });
    m_pageTags->setTags(tags, m_selectedTags);

    QVariantList groups;
    QString lastTitle;
    QString lastColor;
    QVariantList bucket;
    auto flush = [&]() {
        if (bucket.isEmpty())
            return;
        groups.append(QVariantMap{{QStringLiteral("title"), lastTitle},
                                  {QStringLiteral("color"), lastColor},
                                  {QStringLiteral("tags"), bucket}});
        bucket.clear();
    };
    for (const BooruTag &tag : tags) {
        if (m_selectedTags.contains(tag.name, Qt::CaseInsensitive))
            continue;
        const QString title = tagTypeTitle(tag.type);
        if (title != lastTitle) {
            flush();
            lastTitle = title;
            lastColor = tagTypeColor(tag.type).name();
        }
        bucket.append(QVariantMap{{QStringLiteral("name"), tag.name},
                                  {QStringLiteral("postCount"), tag.postCount},
                                  {QStringLiteral("typeColor"), tagTypeColor(tag.type).name()},
                                  {QStringLiteral("selected"), false}});
    }
    flush();
    m_pageTagGroups = groups;
    emit pageTagsChanged();
    TagIndexStore::instance().resolve(names, ServerStore::instance().enabledServers());
}

void AppController::refreshViewer() {
    if (m_viewerIndex < 0 || m_viewerIndex >= m_currentPosts.size()) {
        m_viewerTags->setTags({});
        return;
    }
    QVector<BooruTag> tags;
    for (const QString &name : m_currentPosts[m_viewerIndex].tags) {
        BooruTag tag;
        tag.name = name;
        tag.type = TagIndexStore::instance().typeFor(name);
        tags.append(tag);
    }
    m_viewerTags->setTags(tags, m_selectedTags);
    TagIndexStore::instance().resolve(m_currentPosts[m_viewerIndex].tags,
                                      ServerStore::instance().enabledServers());
}

void AppController::stash() {
    const int index = sessionIndex(m_tab);
    if (index < 0)
        return;
    m_sessions[index].posts = m_currentPosts;
    m_sessions[index].scroll = m_scrollOffset;
    if (m_tab == Pools) {
        m_sessions[index].poolDetail = m_poolDetail;
        m_sessions[index].pool = m_openPool;
    }
}

void AppController::restoreOrReload() {
    const int index = sessionIndex(m_tab);
    if (index < 0)
        return;
    const Session &session = m_sessions[index];
    if (!session.fingerprint.isEmpty() && session.fingerprint == fingerprint()) {
        if (m_tab == Pools) {
            m_poolDetail = session.poolDetail;
            m_openPool = session.pool;
            emit poolDetailChanged();
            if (!m_poolDetail) {
                if (m_poolsModel->rowCount() == 0)
                    reloadPools();
                m_scrollOffset = session.scroll;
                emit scrollOffsetChanged();
                return;
            }
        }
        if (!session.posts.isEmpty()) {
            showPosts(session.posts, false);
            m_scrollOffset = session.scroll;
            emit scrollOffsetChanged();
            m_status = QStringLiteral("%1 posts").arg(session.posts.size());
            emit statusChanged();
            if (m_tab == Browse)
                refreshPageTags();
            return;
        }
    }
    m_scrollOffset = 0;
    emit scrollOffsetChanged();
    reloadCurrent();
}

QString AppController::fingerprint() const {
    QStringList hosts;
    for (const BooruServer &server : ServerStore::instance().enabledServers())
        hosts.append(server.host);
    hosts.sort();
    const QString base = hosts.join(QLatin1Char(',')) + QLatin1Char('|') + QString::number(int(filter()));
    switch (m_tab) {
    case Feed: {
        QStringList ids;
        for (const SavedTagSet &set : PersonalFeedStore::instance().personalSets())
            ids.append(set.id);
        return QStringLiteral("f|%1|%2|%3").arg(int(m_channel)).arg(ids.join(QLatin1Char(',')), base);
    }
    case Browse:
        return QStringLiteral("b|") + m_selectedTags.join(QLatin1Char(' ')) + QLatin1Char('|') + base;
    case Pools:
        if (m_poolDetail)
            return QStringLiteral("p|") + m_openPool.globalId() + QLatin1Char('|') + base;
        return QStringLiteral("plist|") + m_poolQuery + QLatin1Char('|') + base;
    case Favorites:
        return QStringLiteral("fav|") + m_favoriteFolderId + QLatin1Char('|')
            + QString::number(FavoriteStore::instance().postsInFolder(m_favoriteFolderId).size()) + QLatin1Char('|')
            + QString::number(int(filter()));
    case Settings:
        return {};
    }
    return base;
}

GallerySection AppController::gallerySection() const {
    switch (m_tab) {
    case Feed:
        return GallerySection::Feed;
    case Favorites:
        return GallerySection::Favorites;
    case Pools:
        return GallerySection::Pools;
    case Browse:
    case Settings:
        return GallerySection::Browse;
    }
    return GallerySection::Browse;
}

RatingFilter AppController::filter() const {
    return GallerySettings::instance().ratingFilter();
}

FeedAggregator *AppController::activeAggregator() const {
    switch (m_tab) {
    case Feed:
        return m_feedAgg;
    case Browse:
        return m_browseAgg;
    case Pools:
        return m_poolDetail ? m_poolAgg : nullptr;
    case Favorites:
    case Settings:
        return nullptr;
    }
    return nullptr;
}

QVector<BooruServer> AppController::poolServers() const {
    QVector<BooruServer> result;
    for (const BooruServer &server : ServerStore::instance().enabledServers()) {
        if (BooruClient::supportsPools(server.flavor))
            result.append(server);
    }
    return result;
}

QStringList AppController::serverPalette() const {
    return {
        QStringLiteral("#4A90E2"), QStringLiteral("#E23B3B"), QStringLiteral("#4CB56E"),
        QStringLiteral("#F29A3D"), QStringLiteral("#A170DB"), QStringLiteral("#EB73B3"),
        QStringLiteral("#40BABA"), QStringLiteral("#D9BF3D"), QStringLiteral("#5C6BC0"),
        QStringLiteral("#26A69A"), QStringLiteral("#EF5350"), QStringLiteral("#66BB6A"),
        QStringLiteral("#FFA726"), QStringLiteral("#AB47BC"), QStringLiteral("#EC407A"),
        QStringLiteral("#29B6F6"), QStringLiteral("#8D6E63"), QStringLiteral("#78909C"),
        QStringLiteral("#9CCC65"), QStringLiteral("#FF7043"),
    };
}

void AppController::requestPoolPreviews(const QVector<BooruPool> &pools, int startRow) {
    for (int i = 0; i < pools.size(); ++i) {
        const BooruPool pool = pools[i];
        const int row = startRow + i;
        const BooruServer server = ServerStore::instance().serverFor(pool.serverId);
        if (server.host.isEmpty())
            continue;
        BooruClient::fetchPoolPosts(server, pool.id, 1, [this, row, id = pool.globalId()](QVector<BooruPost> posts, QString) {
            if (row < 0 || row >= m_poolsModel->rowCount())
                return;
            if (m_poolsModel->at(row).globalId() != id)
                return;
            QStringList urls;
            for (const BooruPost &post : posts) {
                if (post.previewUrl.isEmpty())
                    continue;
                urls.append(post.previewUrl.toString());
                if (urls.size() >= 6)
                    break;
            }
            m_poolsModel->setPreviewUrls(row, urls);
        });
    }
}

QString AppController::downloadFolder() const {
    return GallerySettings::instance().downloadFolder();
}

void AppController::setDownloadFolder(const QString &path) {
    GallerySettings::instance().setDownloadFolder(localFolderPath(path));
}

bool AppController::askDownloadFolder() const {
    return GallerySettings::instance().askDownloadFolder();
}

void AppController::setAskDownloadFolder(bool ask) {
    GallerySettings::instance().setAskDownloadFolder(ask);
}

SelectionStore *AppController::selectedPosts() const {
    return &SelectionStore::instance();
}

DownloadStore *AppController::downloads() const {
    return &DownloadStore::instance();
}

QString AppController::lastFavoriteFolderId() const {
    return FavoriteStore::instance().lastFolderId();
}

void AppController::setFavoriteFolderId(const QString &id) {
    const QString next = id.isEmpty() ? defaultFavoriteFolderId() : id;
    if (m_favoriteFolderId == next)
        return;
    m_favoriteFolderId = next;
    emit favoriteFolderChanged();
    m_sessions[SecFavorites].fingerprint.clear();
    if (m_tab == Favorites)
        reloadFavorites();
}

void AppController::prepareLayout(double innerWidth) {
    m_layoutWidth = innerWidth;
    rebuildLayout();
}

void AppController::rebuildLayout() {
    m_layout = buildGalleryLayout(m_currentPosts, m_layoutWidth,
                                  GallerySettings::instance().preferredTileWidth(gallerySection()),
                                  GallerySettings::instance().tilingMode(), compact());
    emit layoutChanged();
}

double AppController::itemX(int index) const {
    if (index < 0 || index >= m_layout.frames.size())
        return 0;
    return m_layout.frames[index].x();
}

double AppController::itemY(int index) const {
    if (index < 0 || index >= m_layout.frames.size())
        return 0;
    return m_layout.frames[index].y();
}

double AppController::itemH(int index) const {
    if (index < 0 || index >= m_layout.frames.size())
        return 0;
    return m_layout.frames[index].height();
}

QVariantList AppController::indexesInYRange(double top, double bottom) const {
    QVariantList out;
    if (bottom < top)
        std::swap(top, bottom);
    for (int i = 0; i < m_layout.frames.size(); ++i) {
        const QRectF &frame = m_layout.frames[i];
        if (frame.bottom() >= top && frame.top() <= bottom)
            out.append(i);
    }
    return out;
}

void AppController::toggleSelectedAt(int index) {
    if (index < 0 || index >= m_currentPosts.size())
        return;
    SelectionStore::instance().toggle(m_currentPosts[index]);
}

void AppController::openPeek(int index) {
    if (index < 0 || index >= m_currentPosts.size())
        return;
    m_peekOpen = true;
    m_peekIndex = index;
    refreshPeek();
    emit peekChanged();
}

void AppController::closePeek() {
    m_peekOpen = false;
    emit peekChanged();
}

void AppController::peekSelect() {
    if (m_peekIndex < 0 || m_peekIndex >= m_currentPosts.size())
        return;
    SelectionStore::instance().toggle(m_currentPosts[m_peekIndex]);
}

void AppController::peekFavorite() {
    if (m_peekIndex < 0 || m_peekIndex >= m_currentPosts.size())
        return;
    const BooruPost &post = m_currentPosts[m_peekIndex];
    if (FavoriteStore::instance().contains(post.globalId()))
        FavoriteStore::instance().unfavorite(post.globalId());
    else
        requestFavoritePosts({post});
}

void AppController::openPeekSite() {
    if (m_peekIndex < 0 || m_peekIndex >= m_currentPosts.size())
        return;
    const BooruPost &post = m_currentPosts[m_peekIndex];
    QDesktopServices::openUrl(postPageUrl(post, ServerStore::instance().serverFor(post.serverId).flavor));
}

void AppController::savePeekFile(const QString &path) {
    const QString dest = localFolderPath(path);
    if (dest.isEmpty() || m_peekIndex < 0 || m_peekIndex >= m_currentPosts.size())
        return;
    const BooruPost &post = m_currentPosts[m_peekIndex];
    const QUrl url = post.fileUrl.isEmpty() ? post.viewerUrl() : post.fileUrl;
    HttpClient::instance().download(url, [dest](QByteArray data, QString) {
        QFile file(dest);
        if (file.open(QIODevice::WriteOnly))
            file.write(data);
    });
}

QString AppController::suggestedPeekName() const {
    if (m_peekIndex < 0 || m_peekIndex >= m_currentPosts.size())
        return QStringLiteral("post.jpg");
    return saveNameFor(m_currentPosts[m_peekIndex]);
}

QString AppController::peekUrl() const {
    if (m_peekIndex < 0 || m_peekIndex >= m_currentPosts.size())
        return {};
    return m_currentPosts[m_peekIndex].viewerUrl().toString();
}

QString AppController::peekMeta() const {
    if (m_peekIndex < 0 || m_peekIndex >= m_currentPosts.size())
        return {};
    const BooruPost &post = m_currentPosts[m_peekIndex];
    return QStringLiteral("%1  #%2").arg(post.serverId).arg(post.id);
}

bool AppController::peekFavorited() const {
    if (m_peekIndex < 0 || m_peekIndex >= m_currentPosts.size())
        return false;
    return FavoriteStore::instance().contains(m_currentPosts[m_peekIndex].globalId());
}

double AppController::peekAspect() const {
    if (m_peekIndex < 0 || m_peekIndex >= m_currentPosts.size())
        return 1;
    return m_currentPosts[m_peekIndex].aspectRatio();
}

void AppController::refreshPeek() {
    if (m_peekIndex < 0 || m_peekIndex >= m_currentPosts.size()) {
        m_peekTags->setTags({});
        m_peekTagGroups.clear();
        return;
    }
    QVector<BooruTag> tags;
    for (const QString &name : m_currentPosts[m_peekIndex].tags) {
        BooruTag tag;
        tag.name = name;
        tag.type = TagIndexStore::instance().typeFor(name);
        tags.append(tag);
    }
    m_peekTags->setTags(tags, m_selectedTags);

    auto typeOrder = [](TagType type) {
        switch (type) {
        case TagType::Copyright:
            return 0;
        case TagType::Character:
            return 1;
        case TagType::Artist:
            return 2;
        case TagType::General:
            return 3;
        case TagType::Meta:
            return 4;
        }
        return 3;
    };
    std::sort(tags.begin(), tags.end(), [&](const BooruTag &a, const BooruTag &b) {
        if (typeOrder(a.type) != typeOrder(b.type))
            return typeOrder(a.type) < typeOrder(b.type);
        return a.name < b.name;
    });

    QVariantList groups;
    QString lastTitle;
    QString lastColor;
    QVariantList bucket;
    auto flush = [&]() {
        if (bucket.isEmpty())
            return;
        groups.append(QVariantMap{{QStringLiteral("title"), lastTitle},
                                  {QStringLiteral("color"), lastColor},
                                  {QStringLiteral("tags"), bucket}});
        bucket.clear();
    };
    for (const BooruTag &tag : tags) {
        const QString title = tagTypeTitle(tag.type);
        if (title != lastTitle) {
            flush();
            lastTitle = title;
            lastColor = tagTypeColor(tag.type).name();
        }
        bucket.append(QVariantMap{{QStringLiteral("name"), tag.name},
                                  {QStringLiteral("typeColor"), tagTypeColor(tag.type).name()},
                                  {QStringLiteral("selected"),
                                   m_selectedTags.contains(tag.name, Qt::CaseInsensitive)}});
    }
    flush();
    m_peekTagGroups = groups;
    if (m_peekOpen)
        emit peekChanged();
    TagIndexStore::instance().resolve(m_currentPosts[m_peekIndex].tags,
                                      ServerStore::instance().enabledServers());
}

void AppController::syncTagSelectionViews() {
    m_pageTags->setSelected(m_selectedTags);
    m_viewerTags->setSelected(m_selectedTags);
    m_peekTags->setSelected(m_selectedTags);
    if (m_peekOpen)
        refreshPeek();
    if (m_tab == Browse)
        refreshPageTags();
}

void AppController::requestFavoritePosts(const QVector<BooruPost> &posts) {
    if (posts.isEmpty())
        return;
    m_pendingFavorites = posts;
    m_pendingFromSelection = false;
    emit favoriteDialogRequested();
}

void AppController::requestFavoriteSelected() {
    const QVector<BooruPost> posts = SelectionStore::instance().posts();
    if (posts.isEmpty())
        return;
    m_pendingFavorites = posts;
    m_pendingFromSelection = true;
    emit favoriteDialogRequested();
}

void AppController::confirmFavorite(const QString &folderId) {
    if (m_pendingFavorites.isEmpty())
        return;
    FavoriteStore::instance().addMany(m_pendingFavorites, folderId);
    if (m_pendingFromSelection)
        SelectionStore::instance().clear();
    m_pendingFromSelection = false;
    m_pendingFavorites.clear();
}

void AppController::confirmFavoriteNew(const QString &name) {
    const QString id = FavoriteStore::instance().createFolder(name);
    confirmFavorite(id);
}

void AppController::enqueueDownloads(const QString &folder) {
    QString dest = localFolderPath(folder);
    if (dest.isEmpty())
        dest = downloadFolder();
    const QVector<BooruPost> posts = SelectionStore::instance().takeAll();
    DownloadStore::instance().enqueue(posts, dest);
}

void AppController::createFavoriteFolder(const QString &name) {
    const QString id = FavoriteStore::instance().createFolder(name);
    if (!id.isEmpty())
        setFavoriteFolderId(id);
}

void AppController::renameFavoriteFolder(const QString &id, const QString &name) {
    FavoriteStore::instance().renameFolder(id, name);
}

void AppController::deleteFavoriteFolder(const QString &id, bool deletePosts) {
    FavoriteStore::instance().deleteFolder(id, deletePosts);
    if (m_favoriteFolderId == id)
        setFavoriteFolderId(defaultFavoriteFolderId());
}

QString AppController::saveNameFor(const BooruPost &post) const {
    QString ext = post.fileExt;
    if (ext.isEmpty())
        ext = QStringLiteral("jpg");
    return QStringLiteral("%1_%2.%3").arg(post.serverId, QString::number(post.id), ext);
}

QString AppController::suggestedSaveName() const {
    if (m_viewerIndex < 0 || m_viewerIndex >= m_currentPosts.size())
        return QStringLiteral("post.jpg");
    return saveNameFor(m_currentPosts[m_viewerIndex]);
}
