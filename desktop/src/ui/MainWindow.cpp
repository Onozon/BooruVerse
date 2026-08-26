#include "ui/MainWindow.h"

#include "api/BooruClient.h"
#include "api/FeedAggregator.h"
#include "api/PoolAggregator.h"
#include "core/FavoriteStore.h"
#include "core/HttpClient.h"
#include "core/GallerySettings.h"
#include "core/PersonalFeedStore.h"
#include "core/SavedTagSetStore.h"
#include "core/ServerStore.h"
#include "core/TagIndexStore.h"
#include "ui/PoolListWidget.h"
#include "ui/PostGridWidget.h"
#include "ui/SettingsDialog.h"
#include "ui/TagSidebar.h"
#include "ui/ThumbnailCache.h"
#include "ui/ViewerDialog.h"

#include <algorithm>

#include <QAction>
#include <QComboBox>
#include <QDesktopServices>
#include <QFile>
#include <QFileDialog>
#include <QHash>
#include <QLabel>
#include <QMessageBox>
#include <QSettings>
#include <QSlider>
#include <QSplitter>
#include <QStackedWidget>
#include <QStatusBar>
#include <QTimer>
#include <QToolBar>

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent)
    , m_browseAgg(new FeedAggregator(this))
    , m_feedAgg(new FeedAggregator(this))
    , m_poolAgg(new FeedAggregator(this))
    , m_pools(new PoolAggregator(this))
    , m_cache(new ThumbnailCache(this))
    , m_viewer(new ViewerDialog(this)) {
    setWindowTitle(QStringLiteral("BooruVerse"));
    resize(1320, 840);

    auto *toolbar = addToolBar(QStringLiteral("Main"));
    toolbar->setMovable(false);

    m_section = new QComboBox;
    m_section->addItems({QStringLiteral("Browse"), QStringLiteral("Feed"), QStringLiteral("Favorites"),
                         QStringLiteral("Pools")});
    toolbar->addWidget(m_section);

    m_period = new QComboBox;
    m_period->addItems({QStringLiteral("Personal"), QStringLiteral("Day"), QStringLiteral("Week"),
                        QStringLiteral("Month")});
    m_period->setCurrentIndex(QSettings().value(QStringLiteral("feed/channel"), 0).toInt());
    toolbar->addWidget(m_period);

    m_rating = new QComboBox;
    m_rating->addItems({QStringLiteral("Show All"), QStringLiteral("Hide Explicit"), QStringLiteral("Safe Only")});
    m_rating->setCurrentIndex(int(GallerySettings::instance().ratingFilter()));
    toolbar->addWidget(m_rating);

    m_tiling = new QComboBox;
    m_tiling->addItems({QStringLiteral("Columns"), QStringLiteral("Adaptive")});
    m_tiling->setCurrentIndex(int(GallerySettings::instance().tilingMode()));
    toolbar->addWidget(m_tiling);

    m_scale = new QSlider(Qt::Horizontal);
    m_scale->setRange(72, 360);
    m_scale->setFixedWidth(120);
    m_scale->setToolTip(QStringLiteral("Thumbnail size (Ctrl+wheel on the grid)"));
    toolbar->addWidget(m_scale);

    m_sidebarToggle = toolbar->addAction(QStringLiteral("Sidebar"));
    m_sidebarToggle->setCheckable(true);
    m_sidebarToggle->setChecked(GallerySettings::instance().showsSidebar());
    auto *refresh = toolbar->addAction(QStringLiteral("Refresh"));
    auto *settings = toolbar->addAction(QStringLiteral("Settings"));

    m_tags = new TagSidebar;
    m_poolList = new PoolListWidget;
    m_left = new QStackedWidget;
    m_left->addWidget(m_tags);
    m_left->addWidget(m_poolList);
    m_left->setMinimumWidth(220);
    m_left->setMaximumWidth(320);

    m_grid = new PostGridWidget(m_cache);
    auto *splitter = new QSplitter;
    splitter->addWidget(m_left);
    splitter->addWidget(m_grid);
    splitter->setStretchFactor(1, 1);
    splitter->setSizes({240, 1080});
    setCentralWidget(splitter);

    m_status = new QLabel(QStringLiteral("Ready"));
    statusBar()->addWidget(m_status, 1);

    updateChrome();

    connect(m_section, &QComboBox::currentIndexChanged, this, [this]() {
        stashCurrent();
        updateChrome();
        restoreOrReload();
        m_lastSection = currentSection();
    });
    connect(m_period, &QComboBox::currentIndexChanged, this, [this]() {
        QSettings().setValue(QStringLiteral("feed/channel"), m_period->currentIndex());
        m_sessions[Feed].fingerprint.clear();
        if (currentSection() == Feed)
            reloadFeed();
    });
    connect(m_tiling, &QComboBox::currentIndexChanged, this, [this](int index) {
        GallerySettings::instance().setTilingMode(TilingMode(index));
        applyGallery();
    });
    connect(m_scale, &QSlider::valueChanged, this, [this](int value) {
        persistGalleryScale(value);
        m_grid->setTileExtent(value);
    });
    connect(m_grid, &PostGridWidget::scaleChanged, this, [this](int extent) {
        persistGalleryScale(extent);
        m_scale->blockSignals(true);
        m_scale->setValue(extent);
        m_scale->blockSignals(false);
    });
    connect(&PersonalFeedStore::instance(), &PersonalFeedStore::changed, this, [this]() {
        m_sessions[Feed].fingerprint.clear();
        if (isPersonalFeed())
            reloadFeed();
    });
    connect(&SavedTagSetStore::instance(), &SavedTagSetStore::changed, this, [this]() {
        m_sessions[Feed].fingerprint.clear();
        if (isPersonalFeed())
            reloadFeed();
    });
    connect(m_rating, &QComboBox::currentIndexChanged, this, [this](int index) {
        GallerySettings::instance().setRatingFilter(RatingFilter(index));
        for (Session &session : m_sessions)
            session.fingerprint.clear();
        reloadCurrent();
    });
    connect(m_sidebarToggle, &QAction::toggled, this, [this](bool on) {
        GallerySettings::instance().setShowsSidebar(on);
        updateChrome();
    });
    connect(refresh, &QAction::triggered, this, [this]() {
        m_sessions[currentSection()].fingerprint.clear();
        reloadCurrent();
    });
    connect(settings, &QAction::triggered, this, [this]() {
        SettingsDialog dialog(this);
        dialog.exec();
        m_rating->blockSignals(true);
        m_rating->setCurrentIndex(int(GallerySettings::instance().ratingFilter()));
        m_rating->blockSignals(false);
    });
    connect(&ServerStore::instance(), &ServerStore::changed, this, [this]() {
        for (Session &session : m_sessions)
            session.fingerprint.clear();
        reloadCurrent();
    });
    connect(&FavoriteStore::instance(), &FavoriteStore::changed, this, [this]() {
        if (currentSection() == Favorites && !m_refreshingFavorites)
            reloadFavorites();
    });
    connect(&GallerySettings::instance(), &GallerySettings::changed, this, [this]() {
        m_rating->blockSignals(true);
        m_rating->setCurrentIndex(int(GallerySettings::instance().ratingFilter()));
        m_rating->blockSignals(false);
    });
    auto bindAgg = [this](FeedAggregator *aggregator) {
        connect(aggregator, &FeedAggregator::pageReady, this,
                [this, aggregator](const QVector<BooruPost> &posts, const QString &error) {
                    handlePage(aggregator, posts, error);
                });
        connect(aggregator, &FeedAggregator::loadingChanged, this, [this, aggregator](bool loading) {
            if (activeAggregator() != aggregator)
                return;
            m_loadingMore = loading;
            if (loading)
                m_status->setText(QStringLiteral("Loading…"));
        });
    };
    bindAgg(m_browseAgg);
    bindAgg(m_feedAgg);
    bindAgg(m_poolAgg);
    connect(m_pools, &PoolAggregator::pageReady, this, &MainWindow::appendPools);
    connect(m_pools, &PoolAggregator::loadingChanged, this, [this](bool loading) {
        if (currentSection() == Pools && !m_poolDetail)
            m_status->setText(loading ? QStringLiteral("Loading pools…") : m_status->text());
    });
    connect(m_grid, &PostGridWidget::postActivated, this, [this](int index) {
        m_viewer->showPosts(m_posts, index);
    });
    connect(m_grid, &PostGridWidget::nearBottom, this, [this]() {
        if (!m_loadingMore && activeAggregator())
            activeAggregator()->loadMore();
    });
    connect(m_grid, &PostGridWidget::favoriteRequested, this, [this](int index) {
        if (index >= 0 && index < m_posts.size())
            FavoriteStore::instance().toggle(m_posts[index]);
    });
    connect(m_grid, &PostGridWidget::saveRequested, this, [this](int index) {
        if (index >= 0 && index < m_posts.size())
            savePost(m_posts[index]);
    });
    connect(m_grid, &PostGridWidget::openSiteRequested, this, [this](int index) {
        if (index >= 0 && index < m_posts.size())
            openPostSite(m_posts[index]);
    });
    connect(m_grid, &PostGridWidget::openSourceRequested, this, [this](int index) {
        if (index >= 0 && index < m_posts.size() && !m_posts[index].sourceUrl.isEmpty())
            QDesktopServices::openUrl(m_posts[index].sourceUrl);
    });
    connect(m_viewer, &ViewerDialog::nearEnd, this, [this]() {
        if (!m_loadingMore && activeAggregator())
            activeAggregator()->loadMore();
    });
    connect(m_viewer, &ViewerDialog::currentChanged, this, [this](int index) {
        m_grid->setSelectedIndex(index);
    });
    connect(m_tags, &TagSidebar::tagsChanged, this, [this]() {
        if (currentSection() != Browse) {
            stashCurrent();
            m_section->blockSignals(true);
            m_section->setCurrentIndex(Browse);
            m_section->blockSignals(false);
            updateChrome();
            m_lastSection = Browse;
        }
        m_sessions[Browse].fingerprint.clear();
        reloadBrowse();
    });
    connect(m_viewer, &ViewerDialog::tagClicked, this, &MainWindow::applyViewerTag);
    connect(m_poolList, &PoolListWidget::poolActivated, this, &MainWindow::openPool);
    connect(m_poolList, &PoolListWidget::querySubmitted, this, &MainWindow::reloadPools);
    connect(m_poolList, &PoolListWidget::nearBottom, this, [this]() {
        if (currentSection() == Pools)
            m_pools->loadMore();
    });

    auto *suggestTimer = new QTimer(this);
    suggestTimer->setSingleShot(true);
    suggestTimer->setInterval(220);
    connect(m_tags, &TagSidebar::fragmentChanged, this, [suggestTimer](const QString &fragment) {
        suggestTimer->setProperty("fragment", fragment);
        suggestTimer->start();
    });
    connect(suggestTimer, &QTimer::timeout, this, [this, suggestTimer]() {
        const QString fragment = suggestTimer->property("fragment").toString();
        if (fragment.size() < 2) {
            m_tags->setSuggestions({});
            return;
        }
        const QVector<BooruServer> servers = ServerStore::instance().enabledServers();
        if (servers.isEmpty())
            return;
        BooruClient::suggestFromServers(servers, m_tags->tags(), fragment,
                                        [this, fragment](QVector<BooruTag> tags, QString) {
                                            if (m_tags->fragment() != fragment)
                                                return;
                                            m_tags->setSuggestions(tags);
                                        });
    });

    reloadBrowse();
    m_lastSection = Browse;
}

MainWindow::Section MainWindow::currentSection() const {
    return Section(m_section->currentIndex());
}

RatingFilter MainWindow::currentFilter() const {
    return RatingFilter(m_rating->currentIndex());
}

PopularPeriod MainWindow::currentPeriod() const {
    return PopularPeriod(qMax(m_period->currentIndex() - 1, 0));
}

FeedChannel MainWindow::currentChannel() const {
    return FeedChannel(m_period->currentIndex());
}

bool MainWindow::isPersonalFeed() const {
    return currentSection() == Feed && currentChannel() == FeedChannel::Personal;
}

GallerySection MainWindow::currentGallerySection() const {
    switch (currentSection()) {
    case Browse:
        return GallerySection::Browse;
    case Feed:
        return GallerySection::Feed;
    case Favorites:
        return GallerySection::Favorites;
    case Pools:
        return GallerySection::Pools;
    }
    return GallerySection::Browse;
}

QVector<BooruServer> MainWindow::poolServers() const {
    QVector<BooruServer> result;
    for (const BooruServer &server : ServerStore::instance().enabledServers()) {
        if (BooruClient::supportsPools(server.flavor))
            result.append(server);
    }
    return result;
}

FeedAggregator *MainWindow::activeAggregator() const {
    switch (currentSection()) {
    case Browse:
        return m_browseAgg;
    case Feed:
        return m_feedAgg;
    case Pools:
        return m_poolDetail ? m_poolAgg : nullptr;
    case Favorites:
        return nullptr;
    }
    return nullptr;
}

MainWindow::Section MainWindow::ownerFor(FeedAggregator *aggregator) const {
    if (aggregator == m_browseAgg)
        return Browse;
    if (aggregator == m_feedAgg)
        return Feed;
    return Pools;
}

QString MainWindow::fingerprint() const {
    QStringList hosts;
    for (const BooruServer &server : ServerStore::instance().enabledServers())
        hosts.append(server.host);
    hosts.sort();
    const QString base = hosts.join(QLatin1Char(',')) + QLatin1Char('|') + QString::number(int(currentFilter()));
    switch (currentSection()) {
    case Browse:
        return QStringLiteral("b|") + m_tags->joined() + QLatin1Char('|') + base;
    case Feed: {
        QStringList ids;
        for (const SavedTagSet &set : PersonalFeedStore::instance().personalSets())
            ids.append(set.id);
        return QStringLiteral("f|%1|%2|%3").arg(int(currentChannel())).arg(ids.join(QLatin1Char(',')), base);
    }
    case Favorites:
        return QStringLiteral("fav|") + QString::number(FavoriteStore::instance().posts().size()) + QLatin1Char('|')
            + QString::number(int(currentFilter()));
    case Pools:
        if (m_poolDetail)
            return QStringLiteral("p|") + m_openPool.globalId() + QLatin1Char('|') + base;
        return QStringLiteral("plist|") + m_poolList->query() + QLatin1Char('|') + base;
    }
    return base;
}

void MainWindow::updateChrome() {
    const Section section = currentSection();
    m_period->setVisible(section == Feed);
    const bool showLeft = GallerySettings::instance().showsSidebar() && (section == Browse || section == Pools);
    m_left->setVisible(showLeft);
    m_sidebarToggle->setVisible(section == Browse || section == Pools);
    m_left->setCurrentWidget(section == Pools ? static_cast<QWidget *>(m_poolList)
                                              : static_cast<QWidget *>(m_tags));
    applyGallery();
}

void MainWindow::applyGallery() {
    const GallerySection section = currentGallerySection();
    const int extent = GallerySettings::instance().tileExtent(section);
    m_grid->setTilingMode(GallerySettings::instance().tilingMode());
    m_grid->setTileExtent(extent);
    m_scale->blockSignals(true);
    m_scale->setValue(extent);
    m_scale->blockSignals(false);
    m_tiling->blockSignals(true);
    m_tiling->setCurrentIndex(int(GallerySettings::instance().tilingMode()));
    m_tiling->blockSignals(false);
}

void MainWindow::persistGalleryScale(int extent) {
    GallerySettings::instance().setTileExtent(currentGallerySection(), extent);
}

void MainWindow::stashCurrent() {
    Session &session = m_sessions[m_lastSection];
    session.posts = m_posts;
    session.scroll = m_grid->scrollValue();
}

void MainWindow::showSession(const Session &session) {
    m_posts = session.posts;
    m_grid->setPosts(m_posts, session.scroll);
    if (currentSection() == Browse)
        refreshPageTags();
    m_status->setText(QStringLiteral("%1 posts").arg(m_posts.size()));
}

void MainWindow::restoreOrReload() {
    const Session &session = m_sessions[currentSection()];
    if (!session.fingerprint.isEmpty() && session.fingerprint == fingerprint() && !session.posts.isEmpty()) {
        showSession(session);
        return;
    }
    reloadCurrent();
}

void MainWindow::reloadCurrent() {
    switch (currentSection()) {
    case Browse:
        reloadBrowse();
        break;
    case Feed:
        reloadFeed();
        break;
    case Favorites:
        reloadFavorites();
        break;
    case Pools:
        reloadPools();
        break;
    }
}

void MainWindow::reloadBrowse() {
    if (currentSection() != Browse)
        return;
    m_poolDetail = false;
    m_posts.clear();
    m_grid->clear();
    m_tags->setPageTags({});
    m_loadingMore = true;
    m_browseAgg->reset(ServerStore::instance().enabledServers(), m_tags->joined(), currentFilter());
    m_sessions[Browse].fingerprint = fingerprint();
}

void MainWindow::reloadFeed() {
    m_poolDetail = false;
    m_posts.clear();
    m_grid->clear();
    if (currentChannel() == FeedChannel::Personal) {
        QVector<QStringList> tagSets;
        for (const SavedTagSet &set : PersonalFeedStore::instance().personalSets())
            tagSets.append(set.tags);
        if (tagSets.isEmpty()) {
            m_loadingMore = false;
            m_sessions[Feed].posts.clear();
            m_sessions[Feed].fingerprint = fingerprint();
            m_status->setText(QStringLiteral("Save a tag set and check it for Personal feed"));
            return;
        }
        m_loadingMore = true;
        m_feedAgg->loadPersonal(ServerStore::instance().enabledServers(), tagSets, currentFilter());
        m_sessions[Feed].fingerprint = fingerprint();
        return;
    }
    m_loadingMore = true;
    m_feedAgg->loadPopular(ServerStore::instance().enabledServers(), currentPeriod(), currentFilter());
    m_sessions[Feed].fingerprint = fingerprint();
}

void MainWindow::reloadFavorites() {
    m_poolDetail = false;
    m_posts.clear();
    for (const BooruPost &post : FavoriteStore::instance().posts()) {
        if (post.allowedBy(currentFilter()))
            m_posts.append(post);
    }
    m_grid->setPosts(m_posts, m_sessions[Favorites].scroll);
    m_sessions[Favorites].posts = m_posts;
    m_sessions[Favorites].fingerprint = fingerprint();
    m_status->setText(QStringLiteral("%1 favorites").arg(m_posts.size()));
    refreshFavoriteSnapshots();
}

void MainWindow::refreshFavoriteSnapshots() {
    if (m_refreshingFavorites)
        return;
    m_refreshingFavorites = true;
    const QVector<BooruPost> posts = FavoriteStore::instance().posts();
    auto *pending = new int(0);
    for (const BooruPost &post : posts) {
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
            if (currentSection() != Favorites)
                return;
            m_posts.clear();
            for (const BooruPost &item : FavoriteStore::instance().posts()) {
                if (item.allowedBy(currentFilter()))
                    m_posts.append(item);
            }
            m_grid->setPosts(m_posts, m_sessions[Favorites].scroll);
            m_status->setText(QStringLiteral("%1 favorites").arg(m_posts.size()));
        });
    }
    if (*pending == 0) {
        delete pending;
        m_refreshingFavorites = false;
    }
}

void MainWindow::reloadPools() {
    m_poolDetail = false;
    m_posts.clear();
    m_grid->clear();
    m_poolList->clear();
    const QVector<BooruServer> servers = poolServers();
    if (servers.isEmpty()) {
        m_poolList->setEmptyHint(QStringLiteral("Enable yande.re or konachan.com in Settings."));
        m_status->setText(QStringLiteral("No pool-capable boards enabled"));
        return;
    }
    m_poolList->setEmptyHint(QStringLiteral("Loading pools…"));
    m_status->setText(QStringLiteral("Loading pools…"));
    m_pools->reset(servers, m_poolList->query());
    m_sessions[Pools].fingerprint = fingerprint();
}

void MainWindow::openPool(const BooruPool &pool) {
    m_poolDetail = true;
    m_openPool = pool;
    m_posts.clear();
    m_grid->clear();
    m_loadingMore = true;
    const BooruServer server = ServerStore::instance().serverFor(pool.serverId);
    m_poolAgg->loadPool(server, pool.id, currentFilter());
    m_sessions[Pools].fingerprint = fingerprint();
    m_status->setText(pool.displayName());
}

void MainWindow::handlePage(FeedAggregator *source, const QVector<BooruPost> &posts, const QString &error) {
    const Section owner = ownerFor(source);
    if (currentSection() != owner) {
        m_sessions[owner].posts += posts;
        return;
    }
    appendPosts(posts, error);
    m_sessions[owner].posts = m_posts;
    if (m_viewer->isVisible())
        m_viewer->appendPosts(posts);
}

void MainWindow::appendPosts(const QVector<BooruPost> &posts, const QString &error) {
    const Section section = currentSection();
    if (section == Favorites || (section == Pools && !m_poolDetail))
        return;
    if (m_posts.isEmpty())
        m_grid->setPosts(posts);
    else
        m_grid->appendPosts(posts);
    m_posts += posts;
    if (section == Browse)
        refreshPageTags();
    QString text = QStringLiteral("%1 posts").arg(m_posts.size());
    if (!error.isEmpty())
        text += QStringLiteral(" — ") + error.split(QLatin1Char('\n')).first();
    m_status->setText(text);
}

void MainWindow::appendPools(const QVector<BooruPool> &pools, const QString &error) {
    if (currentSection() != Pools)
        return;
    if (m_poolList->query().isEmpty() && pools.isEmpty() && error.isEmpty())
        m_poolList->setEmptyHint(QStringLiteral("No pools found."));
    m_poolList->appendPools(pools);
    QString text = QStringLiteral("Pools");
    if (!error.isEmpty())
        text += QStringLiteral(" — ") + error.split(QLatin1Char('\n')).first();
    if (!m_poolDetail)
        m_status->setText(text);
}

void MainWindow::refreshPageTags() {
    const int start = qMax(0, m_posts.size() - 40);
    QHash<QString, int> counts;
    QStringList names;
    for (int i = start; i < m_posts.size(); ++i) {
        for (const QString &tag : m_posts[i].tags) {
            if (tag.isEmpty())
                continue;
            counts[tag] += 1;
            if (!names.contains(tag))
                names.append(tag);
        }
    }
    QVector<BooruTag> tags;
    tags.reserve(counts.size());
    for (auto it = counts.cbegin(); it != counts.cend(); ++it) {
        BooruTag tag;
        tag.name = it.key();
        tag.postCount = it.value();
        tag.type = TagIndexStore::instance().typeFor(tag.name);
        tags.append(tag);
    }
    std::sort(tags.begin(), tags.end(), [](const BooruTag &a, const BooruTag &b) {
        if (a.postCount != b.postCount)
            return a.postCount > b.postCount;
        return a.name < b.name;
    });
    m_tags->setPageTags(tags);
    TagIndexStore::instance().resolve(names, ServerStore::instance().enabledServers());
}

void MainWindow::applyViewerTag(const QString &tag) {
    const bool wasBrowse = currentSection() == Browse;
    const bool already = m_tags->tags().contains(tag.trimmed().toLower());
    if (!wasBrowse) {
        stashCurrent();
        m_section->blockSignals(true);
        m_section->setCurrentIndex(Browse);
        m_section->blockSignals(false);
        updateChrome();
        m_lastSection = Browse;
    }
    if (!already)
        m_tags->addTag(tag);
    else
        reloadBrowse();
}

void MainWindow::savePost(const BooruPost &post) {
    QString ext = post.fileExt;
    if (ext.isEmpty())
        ext = post.fileUrl.path().section(QLatin1Char('.'), -1);
    if (ext.isEmpty())
        ext = QStringLiteral("jpg");
    const QUrl url = post.fileUrl.isEmpty() ? post.viewerUrl() : post.fileUrl;
    const QString suggested = QStringLiteral("%1_%2.%3").arg(post.serverId, QString::number(post.id), ext);
    const QString path = QFileDialog::getSaveFileName(this, QStringLiteral("Save file"), suggested);
    if (path.isEmpty())
        return;
    HttpClient::instance().get(url, {}, [this, path](QByteArray data, QString error) {
        if (!error.isEmpty() || data.isEmpty()) {
            QMessageBox::warning(this, QStringLiteral("Save"),
                                 error.isEmpty() ? QStringLiteral("Download failed.") : error);
            return;
        }
        QFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size())
            QMessageBox::warning(this, QStringLiteral("Save"), QStringLiteral("Couldn't write the file."));
    });
}

void MainWindow::openPostSite(const BooruPost &post) {
    const BooruServer server = ServerStore::instance().serverFor(post.serverId);
    QDesktopServices::openUrl(postPageUrl(post, server.flavor));
}
