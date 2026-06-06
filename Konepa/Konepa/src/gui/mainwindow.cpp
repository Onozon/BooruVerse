#include "gui/mainwindow.h"
#include <QMessageBox>
#include <QStatusBar>
#include <QDebug>
#include <QGridLayout>
#include <QCheckBox>
#include <QGroupBox>
#include <QMenuBar>
#include <QMenu>
#include <QAction>
#include <QScrollArea>
#include <QFileDialog>
#include <QDir>
#include <QComboBox>
#include <QSplitter>
#include <QFrame>
#include <QThread>
#include <QEventLoop>
#include <QTimer>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonValue>
#include <QPointer>
#include <QPainter>
#include <QPainterPath>
#include <QPixmapCache>
#include "gui/imageprocessor.h"
#include "core/lockmanager.h"
#include "core/threadpool.h"
#include "core/mediadownloadmanager.h"
#include <QtConcurrent>
#include <QFutureWatcher>

MainWindow::MainWindow(QWidget *parent)
    : QMainWindow(parent)
    , m_isDownloading(false)
    , m_downloadPath("downloads")
    , m_artistsSearchOffset(0)
    , m_isAppendingArtists(false)
    , m_lastSearchQuery("")
{
    m_parser = new KemonoParser(this);
    m_cacheManager = new CacheManager(this);
    m_historyManager = new HistoryManager();
    m_mediaNetworkManager = new QNetworkAccessManager(this);
    // Отключаем HTTP/2 для избежания ошибок "Server refused a stream"
    m_mediaNetworkManager->setProperty("http2Allowed", false);
    // Не подключаем сигнал finished к менеджеру - будем подключать к каждому reply отдельно
    
    // Ограничиваем размер кэша QPixmap (50MB)
    QPixmapCache::setCacheLimit(50 * 1024);
    
    // Инициализируем состояния секций
    qDebug() << "Initializing section states...";
    m_sectionStates.clear();
    for (int i = 0; i < 3; ++i) {
        SectionState state;
        state.currentTab = 0;
        state.postsPage = 0;
        m_sectionStates.append(state);
    }
    qDebug() << "Section states initialized. Count:" << m_sectionStates.size();
    
    // Создаем поток для обработки изображений
    m_imageProcessorThread = new QThread(this);
    m_imageProcessor = new ImageProcessor();
    m_imageProcessor->moveToThread(m_imageProcessorThread);
    connect(m_imageProcessor, &ImageProcessor::imageProcessed, this, &MainWindow::onImageProcessed);
    connect(m_imageProcessor, &ImageProcessor::processingFailed, this, &MainWindow::onImageProcessingFailed);
    m_imageProcessorThread->start();
    
    qDebug() << "Starting UI setup...";
    setupUI();
    qDebug() << "UI setup complete";
    
    qDebug() << "Starting connections setup...";
    setupConnections();
    qDebug() << "Connections setup complete";
    
    qDebug() << "Starting menu setup...";
    setupMenu();
    qDebug() << "Menu setup complete";
    
    // При первом запуске загружаем пользователей из кэша или с сервера
    // Делаем это через QTimer, чтобы UI успел полностью инициализироваться
    QTimer::singleShot(100, this, [this]() {
        qDebug() << "Loading artists from cache or server...";
        loadArtistsFromCacheOrServer();
        qDebug() << "Initialization complete";
    });
}

MainWindow::~MainWindow()
{
    // Останавливаем поток обработки изображений
    if (m_imageProcessorThread) {
        m_imageProcessorThread->quit();
        m_imageProcessorThread->wait(1000); // Ждем максимум 1 секунду
        if (m_imageProcessorThread->isRunning()) {
            m_imageProcessorThread->terminate();
            m_imageProcessorThread->wait(1000);
        }
    }
    
    // Удаляем процессор изображений
    if (m_imageProcessor) {
        m_imageProcessor->deleteLater();
    }
    
    // Отменяем все активные сетевые запросы
    if (m_mediaNetworkManager) {
        m_mediaNetworkManager->clearAccessCache();
    }
}

void MainWindow::closeEvent(QCloseEvent* event)
{
    // Останавливаем поток обработки изображений
    if (m_imageProcessorThread) {
        m_imageProcessorThread->quit();
        m_imageProcessorThread->wait(1000); // Ждем максимум 1 секунду
        if (m_imageProcessorThread->isRunning()) {
            m_imageProcessorThread->terminate();
            m_imageProcessorThread->wait(1000);
        }
    }
    
    // Отменяем все активные сетевые запросы
    if (m_mediaNetworkManager) {
        m_mediaNetworkManager->clearAccessCache();
    }
    
    // Принимаем событие закрытия
    event->accept();
}

bool MainWindow::eventFilter(QObject* obj, QEvent* event)
{
    if (event->type() == QEvent::MouseButtonRelease) {
        QWidget* widget = qobject_cast<QWidget*>(obj);
        if (widget && widget->property("postData").isValid()) {
            Post post = widget->property("postData").value<Post>();
            int sectionIndex = widget->property("sectionIndex").toInt();
            onPostSelected(sectionIndex, post);
            return true;
        }
    }
    return QMainWindow::eventFilter(obj, event);
}

void MainWindow::setupUI()
{
    setWindowTitle("Konepa");
    setGeometry(100, 100, 1500, 950);
    
    // Light macOS-style theme
    setStyleSheet(R"(
        QMainWindow {
            background: rgba(246, 246, 246, 0.95);
        }
        QScrollArea {
            background: transparent;
            border: none;
        }
        QScrollBar:vertical {
            background: transparent;
            width: 8px;
            border-radius: 4px;
            margin: 0;
        }
        QScrollBar::handle:vertical {
            background: rgba(0,0,0,0.15);
            border-radius: 4px;
            min-height: 40px;
        }
        QScrollBar::handle:vertical:hover {
            background: rgba(0,0,0,0.25);
        }
        QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical {
            height: 0;
        }
        QScrollBar:horizontal {
            background: transparent;
            height: 8px;
            border-radius: 4px;
        }
        QScrollBar::handle:horizontal {
            background: rgba(0,0,0,0.15);
            border-radius: 4px;
            min-width: 40px;
        }
        QScrollBar::handle:horizontal:hover {
            background: rgba(0,0,0,0.25);
        }
        QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal {
            width: 0;
        }
        QLineEdit {
            background: rgba(255,255,255,0.8);
            border: 1px solid rgba(0,0,0,0.1);
            border-radius: 8px;
            padding: 10px 14px;
            color: #1d1d1f;
            font-size: 14px;
            selection-background-color: #007AFF;
        }
        QLineEdit:focus {
            border: 1px solid #007AFF;
            background: #fff;
        }
        QLineEdit::placeholder {
            color: rgba(0,0,0,0.4);
        }
        QComboBox {
            background: rgba(255,255,255,0.8);
            border: 1px solid rgba(0,0,0,0.1);
            border-radius: 8px;
            padding: 8px 12px;
            color: #1d1d1f;
            font-size: 13px;
            min-width: 140px;
        }
        QComboBox:hover {
            background: #fff;
            border: 1px solid rgba(0,0,0,0.15);
        }
        QComboBox::drop-down {
            border: none;
            width: 24px;
        }
        QComboBox::down-arrow {
            image: none;
            border-left: 4px solid transparent;
            border-right: 4px solid transparent;
            border-top: 5px solid rgba(0,0,0,0.5);
            margin-right: 8px;
        }
        QComboBox QAbstractItemView {
            background: #fff;
            border: 1px solid rgba(0,0,0,0.1);
            border-radius: 8px;
            selection-background-color: #007AFF;
            selection-color: #fff;
            color: #1d1d1f;
            padding: 4px;
        }
        QProgressBar {
            background: rgba(0,0,0,0.08);
            border: none;
            border-radius: 3px;
            height: 5px;
            text-align: center;
        }
        QProgressBar::chunk {
            background: #007AFF;
            border-radius: 3px;
        }
        QStatusBar {
            background: rgba(255,255,255,0.7);
            color: rgba(0,0,0,0.6);
            border-top: 1px solid rgba(0,0,0,0.08);
        }
        QTabWidget::pane {
            border: none;
            background: transparent;
        }
        QTabBar::tab {
            background: rgba(0,0,0,0.04);
            color: rgba(0,0,0,0.6);
            padding: 10px 20px;
            border: none;
            border-radius: 6px 6px 0 0;
            margin-right: 2px;
            font-size: 13px;
            font-weight: 500;
        }
        QTabBar::tab:selected {
            background: rgba(255,255,255,0.8);
            color: #1d1d1f;
        }
        QTabBar::tab:hover:!selected {
            background: rgba(0,0,0,0.06);
            color: #1d1d1f;
        }
    )");

    m_centralWidget = new QWidget(this);
    setCentralWidget(m_centralWidget);

    // Main horizontal layout: sidebar + content
    m_mainLayout = new QHBoxLayout(m_centralWidget);
    m_mainLayout->setContentsMargins(0, 0, 0, 0);
    m_mainLayout->setSpacing(0);

    // Setup sidebar
    setupSidebar();
    
    // Setup content area
    m_contentArea = new QWidget(this);
    m_contentArea->setStyleSheet("background: transparent;");
    m_contentLayout = new QVBoxLayout(m_contentArea);
    m_contentLayout->setContentsMargins(0, 0, 0, 0);
    m_contentLayout->setSpacing(0);
    
    // Add content area to layout first
    m_mainLayout->addWidget(m_contentArea, 1);
    
    // Create sections
    for (int i = 0; i < 3; ++i) {
        setupSection(i == 0 ? "Поиск" : (i == 1 ? "История" : "Оффлайн"), i);
    }
    
    // Show first section by default
    if (m_sectionWidgets.size() > 0) {
        switchToSection(0);
    }

    // Progress bar
    m_progressBar = new QProgressBar(this);
    m_progressBar->setVisible(false);
    m_progressBar->setFixedHeight(6);
    m_contentLayout->addWidget(m_progressBar);

    // Status bar
    m_statusLabel = new QLabel("✨ Готов к работе", this);
    m_statusLabel->setStyleSheet("color: rgba(255,255,255,0.7); padding: 5px 15px;");
    statusBar()->addWidget(m_statusLabel);
    
    // Современная стилизация окна
    setStyleSheet(
        "QMainWindow {"
        "  background-color: #f5f5f5;"
        "}"
        "QTabWidget::pane {"
        "  border: 1px solid #ddd;"
        "  background-color: white;"
        "  border-radius: 4px;"
        "}"
        "QTabBar::tab {"
        "  background-color: #e9ecef;"
        "  color: #495057;"
        "  padding: 8px 16px;"
        "  margin-right: 2px;"
        "  border-top-left-radius: 4px;"
        "  border-top-right-radius: 4px;"
        "}"
        "QTabBar::tab:selected {"
        "  background-color: white;"
        "  color: #2c3e50;"
        "  font-weight: 600;"
        "}"
        "QTabBar::tab:hover {"
        "  background-color: #dee2e6;"
        "}"
        "QPushButton {"
        "  background-color: #2c3e50;"
        "  color: white;"
        "  border: none;"
        "  padding: 8px 16px;"
        "  border-radius: 4px;"
        "  font-size: 13px;"
        "}"
        "QPushButton:hover {"
        "  background-color: #1a252f;"
        "}"
        "QPushButton:pressed {"
        "  background-color: #151d25;"
        "}"
        "QLineEdit {"
        "  border: 1px solid #ced4da;"
        "  border-radius: 4px;"
        "  padding: 6px 12px;"
        "  background-color: white;"
        "  font-size: 13px;"
        "}"
        "QLineEdit:focus {"
        "  border-color: #2c3e50;"
        "  outline: none;"
        "}"
        "QScrollArea {"
        "  border: 1px solid #e0e0e0;"
        "  border-radius: 4px;"
        "  background-color: white;"
        "}"
        "QScrollBar:vertical {"
        "  background-color: #f8f9fa;"
        "  width: 12px;"
        "  border: none;"
        "}"
        "QScrollBar::handle:vertical {"
        "  background-color: #ced4da;"
        "  border-radius: 6px;"
        "  min-height: 20px;"
        "}"
        "QScrollBar::handle:vertical:hover {"
        "  background-color: #adb5bd;"
        "}"
    );
}

// Old UI setup methods removed - using new sidebar-based UI

void MainWindow::setupConnections()
{
    qDebug() << "Setting up connections...";
    
    // Parser signals (always needed)
    if (m_parser) {
        qDebug() << "Connecting parser signals...";
        connect(m_parser, &KemonoParser::artistsFound, this, &MainWindow::onArtistsFound);
        connect(m_parser, &KemonoParser::allArtistsLoaded, this, &MainWindow::onAllArtistsLoaded);
        connect(m_parser, &KemonoParser::popularArtistsLoaded, this, &MainWindow::onPopularArtistsLoaded);
        connect(m_parser, &KemonoParser::recentlyUpdatedArtistsLoaded, this, &MainWindow::onRecentlyUpdatedArtistsLoaded);
        connect(m_parser, &KemonoParser::randomArtistLoaded, this, &MainWindow::onRandomArtistLoaded);
        connect(m_parser, &KemonoParser::postsFound, this, &MainWindow::onPostsFound);
        connect(m_parser, &KemonoParser::allArtistPostsLoaded, this, &MainWindow::onAllArtistPostsLoaded);
        connect(m_parser, &KemonoParser::searchPostsFound, this, &MainWindow::onSearchPostsFound);
        connect(m_parser, &KemonoParser::popularPostsLoaded, this, &MainWindow::onPopularPostsLoaded);
        connect(m_parser, &KemonoParser::recentPostsLoaded, this, &MainWindow::onRecentPostsLoaded);
        connect(m_parser, &KemonoParser::randomPostLoaded, this, &MainWindow::onRandomPostLoaded);
        connect(m_parser, &KemonoParser::postLoaded, this, &MainWindow::onPostLoaded);
        connect(m_parser, &KemonoParser::error, this, &MainWindow::onError);
        qDebug() << "Parser signals connected";
    } else {
        qDebug() << "WARNING: m_parser is null!";
    }
    
    qDebug() << "All connections set up";
}

// onArtistsSearchClicked removed - search is handled in sidebar UI

void MainWindow::onLoadMoreArtists(int sectionIndex)
{
    if (sectionIndex < 0 || sectionIndex >= m_sectionStates.size()) {
        qDebug() << "Invalid section index:" << sectionIndex;
        return;
    }
    
    // Get current search query from the section
    QString query = m_searchInputs[sectionIndex]->text().trimmed();
    if (query.isEmpty()) {
        // Load more from cached artists
        int currentCount = m_artistsLayouts[sectionIndex]->count();
        int nextOffset = currentCount;
        int loadCount = 50;
        
        if (nextOffset < m_allCachedArtists.size()) {
            QList<Artist> moreArtists = m_allCachedArtists.mid(nextOffset, loadCount);
            // Append to existing artists list for pagination
            m_sectionStates[sectionIndex].artists.append(moreArtists);
            displayArtistsInSection(sectionIndex, m_sectionStates[sectionIndex].artists);
        }
    } else {
        // Load more search results - use current count as offset
        int currentCount = m_artistsLayouts[sectionIndex]->count();
        performLocalSearch(query, currentCount, sectionIndex);
    }
}

void MainWindow::performLocalSearch(const QString& query, int offset, int sectionIndex)
{
    // Используем локальный кэш для поиска
    QList<Artist> searchResults;
    QString queryLower = query.toLower();
    
    for (const Artist& artist : m_allCachedArtists) {
        QString name = artist.name().toLower();
        QString service = artist.service().toLower();
        QString id = artist.id().toLower();
        
        if (name.contains(queryLower) || 
            service.contains(queryLower) || 
            id.contains(queryLower)) {
            searchResults.append(artist);
        }
    }
    
    qDebug() << "Found" << searchResults.size() << "artists matching query:" << query;
    
    // Применяем пагинацию
    int pageSize = 50;
    int startIndex = offset;
    int endIndex = qMin(offset + pageSize, searchResults.size());
    
    QList<Artist> displayResults = searchResults.mid(startIndex, endIndex - startIndex);
    
    // Display in current section if it's search section
    if (m_currentSection == 0 && m_sectionStates[0].currentTab == 0) {
        if (offset == 0) {
            // Clear section content
            if (0 < m_artistsLayouts.size()) {
                QGridLayout* layout = m_artistsLayouts[0];
                QLayoutItem* item;
                while ((item = layout->takeAt(0)) != nullptr) {
                    delete item->widget();
                    delete item;
                }
            }
        }
        m_sectionStates[0].artists = searchResults; // Save all search results for pagination
        displayArtistsInSection(0, displayResults);
    }
    
    m_statusLabel->setText(QString("Найдено: %1 (показано %2-%3)").arg(searchResults.size()).arg(startIndex + 1).arg(endIndex));
    
    // Сохраняем результаты для "Загрузить ещё"
    m_allSearchArtists = searchResults;
    m_artistsSearchOffset = endIndex;
}

// Old UI event handlers removed - using new sidebar-based UI

void MainWindow::loadArtistsFromCacheOrServer()
{
    // Проверяем, есть ли кэш пользователей
    if (m_cacheManager->hasCachedArtists()) {
        qDebug() << "Loading artists from cache...";
        QList<QJsonObject> cachedArtists = m_cacheManager->loadAllArtists();
        if (!cachedArtists.isEmpty()) {
            // Конвертируем JSON в Artist объекты
            QList<Artist> artists;
            for (const QJsonObject& obj : cachedArtists) {
                Artist artist = m_parser->parseArtistFromJsonPublic(obj);
                artists.append(artist);
            }
            // Отображаем загруженных пользователей
            onAllArtistsLoaded(artists);
            m_statusLabel->setText(QString("Загружено %1 пользователей из кэша").arg(artists.size()));
            return;
        }
    }
    
    // Если кэша нет, загружаем с сервера
    qDebug() << "No cache found, loading all artists from server...";
    m_statusLabel->setText("Загрузка всех пользователей с сервера...");
    m_parser->getAllArtists();
}

void MainWindow::onAllArtistsLoaded(const QList<Artist>& artists)
{
    qDebug() << "All artists loaded:" << artists.size();
    
    // Сохраняем в кэш
    QList<QJsonObject> artistsJson;
    for (const Artist& artist : artists) {
        QJsonObject obj;
        obj["id"] = artist.id();
        obj["name"] = artist.name();
        obj["service"] = artist.service();
        obj["indexed"] = artist.indexed();
        obj["updated"] = artist.updated();
        obj["url"] = artist.url();
        obj["avatar"] = artist.avatar();
        artistsJson.append(obj);
    }
    m_cacheManager->saveAllArtists(artistsJson);
    
    // Сохраняем в память для поиска
    // Slots are called in main thread via Qt signals, no locks needed
    m_allCachedArtists = artists;
    
    // Display in search section if it's active (with pagination)
    if (m_currentSection == 0 && m_sectionStates[0].currentTab == 0) {
        m_sectionStates[0].artistsPage = 0;
        m_sectionStates[0].artists = m_allCachedArtists; // Save artists for pagination
        displayArtistsInSection(0, m_allCachedArtists);
    }
    
    m_statusLabel->setText(QString("Загружено %1 пользователей").arg(artists.size()));
}

void MainWindow::updateArtistsList()
{
    qDebug() << "Updating artists list from server...";
    m_statusLabel->setText("Обновление списка пользователей с сервера...");
    m_parser->getAllArtists();
}

void MainWindow::updateArtistPosts(const Artist& artist)
{
    qDebug() << "Updating posts for artist:" << artist.name();
    m_statusLabel->setText(QString("Обновление постов для %1...").arg(artist.name()));
    m_parser->getAllArtistPosts(artist);
}

void MainWindow::onPopularArtistsLoaded(const QList<Artist>& artists)
{
    qDebug() << "Popular artists loaded:" << artists.size();
    m_statusLabel->setText(QString("Загружено %1 популярных авторов").arg(artists.size()));
    
    // Slots are called in main thread via Qt signals, no locks needed
    if (m_currentSection == 0 && m_sectionStates[0].currentTab == 0) {
        m_sectionStates[0].artistsPage = 0;
        m_sectionStates[0].artists = artists; // Save artists for pagination
        displayArtistsInSection(0, artists);
    }
}

void MainWindow::onRecentlyUpdatedArtistsLoaded(const QList<Artist>& artists)
{
    qDebug() << "Recently updated artists loaded:" << artists.size();
    m_statusLabel->setText(QString("Загружено %1 недавно обновлённых авторов").arg(artists.size()));
    
    // Slots are called in main thread via Qt signals, no locks needed
    if (m_currentSection == 0 && m_sectionStates[0].currentTab == 0) {
        m_sectionStates[0].artistsPage = 0;
        m_sectionStates[0].artists = artists; // Save artists for pagination
        displayArtistsInSection(0, artists);
    }
}

void MainWindow::onRandomArtistLoaded(const Artist& artist)
{
    qDebug() << "Random artist loaded:" << artist.name();
    m_statusLabel->setText(QString("Случайный автор: %1").arg(artist.name()));
    
    // Открываем посты случайного автора
    // Slots are called in main thread via Qt signals, no locks needed
    if (m_currentSection >= 0 && m_currentSection < m_sectionStates.size()) {
        m_sectionStates[m_currentSection].selectedArtist = artist;
        m_sectionStates[m_currentSection].postsPage = 0;
        
        // Переключаемся на вкладку постов
        if (m_sectionStates[m_currentSection].currentTab != 1) {
            switchToSection(m_currentSection, 1);
        }
        
        // Загружаем посты
        m_parser->getAllArtistPosts(artist);
    }
}

void MainWindow::onSearchPostsFound(const QList<Post>& posts)
{
    qDebug() << "Search posts found:" << posts.size();
    m_statusLabel->setText(QString("Найдено %1 постов").arg(posts.size()));
    
    if (m_currentSection == 0 && m_sectionStates[0].currentTab == 1) {
        displayPostsInSection(0, posts);
    }
}

void MainWindow::onPopularPostsLoaded(const QList<Post>& posts)
{
    qDebug() << "Popular posts loaded:" << posts.size();
    m_statusLabel->setText(QString("Загружено %1 популярных постов").arg(posts.size()));
    
    if (m_currentSection == 0 && m_sectionStates[0].currentTab == 1) {
        displayPostsInSection(0, posts);
    }
}

void MainWindow::onRecentPostsLoaded(const QList<Post>& posts)
{
    qDebug() << "Recent posts loaded:" << posts.size();
    m_statusLabel->setText(QString("Загружено %1 последних постов").arg(posts.size()));
    
    if (m_currentSection == 0 && m_sectionStates[0].currentTab == 1) {
        displayPostsInSection(0, posts);
    }
}

void MainWindow::onRandomPostLoaded(const Post& post)
{
    qDebug() << "Random post loaded:" << post.title();
    m_statusLabel->setText(QString("Случайный пост: %1").arg(post.title()));
    
    // Открываем случайный пост в просмотрщике
    PostViewer* viewer = new PostViewer(post, m_cacheManager, this);
    connect(viewer, &PostViewer::openAuthorRequested, this, &MainWindow::onOpenAuthorFromViewer);
    viewer->show();
}

void MainWindow::loadPostPreviewsInBackground(const QList<Post>& posts)
{
    // Загружаем превью постов в фоновом потоке
    QThread* thread = new QThread(this);
    QObject* worker = new QObject();
    worker->moveToThread(thread);
    
    connect(thread, &QThread::started, [this, posts, worker]() {
        for (const Post& post : posts) {
            QString thumbnailUrl = post.thumbnail();
            if (thumbnailUrl.isEmpty()) {
                QList<QVariantMap> files = post.files();
                if (!files.isEmpty() && files[0].contains("path")) {
                    QString filePath = files[0].value("path").toString();
                    if (filePath.startsWith("/")) {
                        thumbnailUrl = QString("https://kemono.cr%1").arg(filePath);
                    } else {
                        thumbnailUrl = QString("https://kemono.cr/%1").arg(filePath);
                    }
                }
            }
            
            if (!thumbnailUrl.isEmpty()) {
                // Проверяем кэш
                QString cachedPath = m_cacheManager->getCachedPreviewPath(thumbnailUrl);
                if (cachedPath.isEmpty() || !QFile::exists(cachedPath)) {
                    // Загружаем превью
                    QNetworkAccessManager* manager = new QNetworkAccessManager();
                    QString fullUrl = thumbnailUrl;
                    if (!fullUrl.startsWith("http://") && !fullUrl.startsWith("https://")) {
                        if (fullUrl.startsWith("/")) {
                            fullUrl = QString("https://kemono.cr%1").arg(fullUrl);
                        } else {
                            fullUrl = QString("https://kemono.cr/%1").arg(fullUrl);
                        }
                    }
                    
                    QNetworkRequest request;
                    request.setUrl(QUrl(fullUrl));
                    request.setRawHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
                    request.setRawHeader("Referer", "https://kemono.cr/");
                    
                    QNetworkReply* reply = manager->get(request);
                    QEventLoop loop;
                    connect(reply, &QNetworkReply::finished, &loop, &QEventLoop::quit);
                    loop.exec();
                    
                    if (reply->error() == QNetworkReply::NoError) {
                        QByteArray data = reply->readAll();
                        QPixmap pixmap;
                        if (pixmap.loadFromData(data)) {
                            m_cacheManager->cachePreview(thumbnailUrl, pixmap);
                        }
                    }
                    reply->deleteLater();
                    manager->deleteLater();
                }
            }
        }
        worker->deleteLater();
    });
    
    connect(thread, &QThread::finished, thread, &QThread::deleteLater);
    thread->start();
}

// Old UI methods removed - using new sidebar-based UI

void MainWindow::onArtistsFound(const QList<Artist>& artists)
{
    qDebug() << "onArtistsFound called with" << artists.size() << "artists";
    
    // Display in current section if it's search section
    if (m_currentSection == 0 && m_sectionStates[0].currentTab == 0) {
        m_sectionStates[0].artists = artists; // Save artists for pagination
        displayArtistsInSection(0, artists);
    }
    
    m_statusLabel->setText(QString("Найдено авторов: %1").arg(artists.size()));
}


// displayArtistsInList removed - using displayArtistsInSection instead

void MainWindow::displayArtistButton(const Artist& artist, QGridLayout* layout, int row, int col, int sectionIndex)
{
    // Create artist widget - clean macOS card style
    QWidget* artistWidget = new QWidget();
    artistWidget->setObjectName("artistCard");
    QVBoxLayout* artistLayout = new QVBoxLayout(artistWidget);
    artistLayout->setContentsMargins(0, 0, 0, 12);
    artistLayout->setSpacing(0);
    
    // Banner container with avatar overlay
    QWidget* bannerContainer = new QWidget(artistWidget);
    bannerContainer->setFixedHeight(130);
    bannerContainer->setStyleSheet("background: transparent;");
    
    // Banner label with soft gradient
    QLabel* bannerLabel = new QLabel(bannerContainer);
    bannerLabel->setGeometry(0, 0, 240, 80);
    bannerLabel->setScaledContents(true);
    bannerLabel->setStyleSheet(R"(
        QLabel {
            border-top-left-radius: 12px;
            border-top-right-radius: 12px;
            background: qlineargradient(x1:0, y1:0, x2:1, y2:1,
                stop:0 #a8d8ea, stop:0.5 #aa96da, stop:1 #fcbad3);
        }
    )");
    
    // Load banner (only if we have service and id)
    if (!artist.service().isEmpty() && !artist.id().isEmpty()) {
        QString bannerUrl = QString("https://img.kemono.cr/banners/%1/%2")
                                .arg(artist.service(), artist.id());
        loadArtistBanner(bannerLabel, bannerUrl);
    }
    
    // Avatar label (overlapping banner)
    QLabel* avatarLabel = new QLabel(bannerContainer);
    avatarLabel->setGeometry(80, 40, 80, 80);
    avatarLabel->setAlignment(Qt::AlignCenter);
    avatarLabel->setScaledContents(true);
    avatarLabel->setStyleSheet(R"(
        QLabel {
            border: 3px solid #fff;
            border-radius: 40px;
            background: #f5f5f7;
            color: rgba(0,0,0,0.4);
            font-size: 22px;
            font-weight: 600;
        }
    )");
    avatarLabel->setText("...");
    
    // Load avatar
    QString avatarUrl = artist.avatar();
    if (avatarUrl.isEmpty() && !artist.service().isEmpty() && !artist.id().isEmpty()) {
        avatarUrl = QString("https://img.kemono.cr/icons/%1/%2")
                        .arg(artist.service(), artist.id());
    }
    if (!avatarUrl.isEmpty()) {
        loadArtistAvatar(avatarLabel, avatarUrl);
    } else {
        avatarLabel->setText(artist.name().isEmpty() ? "?" : artist.name().left(1).toUpper());
    }
    
    artistLayout->addWidget(bannerContainer);
    
    // Name label
    QLabel* nameLabel = new QLabel(artist.name(), artistWidget);
    nameLabel->setWordWrap(true);
    nameLabel->setAlignment(Qt::AlignCenter);
    nameLabel->setStyleSheet(R"(
        font-weight: 600;
        font-size: 13px;
        color: #1d1d1f;
        margin-top: 6px;
        padding: 0 10px;
        background: transparent;
    )");
    artistLayout->addWidget(nameLabel);
    
    // Service badge
    QLabel* serviceLabel = new QLabel(artist.service().toUpper(), artistWidget);
    serviceLabel->setAlignment(Qt::AlignCenter);
    serviceLabel->setStyleSheet(R"(
        font-size: 10px;
        font-weight: 600;
        color: #007AFF;
        padding: 3px 10px;
        background: rgba(0,122,255,0.1);
        border-radius: 8px;
        margin: 4px 55px;
    )");
    artistLayout->addWidget(serviceLabel);
    
    // Style artist widget as clean card
    artistWidget->setStyleSheet(R"(
        #artistCard {
            border: 1px solid rgba(0,0,0,0.08);
            border-radius: 12px;
            background: rgba(255,255,255,0.8);
        }
        #artistCard:hover {
            border-color: rgba(0,122,255,0.3);
            background: #fff;
        }
    )");
    artistWidget->setMinimumHeight(190);
    artistWidget->setFixedWidth(240);
    
    // Make entire widget clickable
    artistWidget->setCursor(Qt::PointingHandCursor);
    artistWidget->installEventFilter(new ArtistClickFilter(artist, this, [this, artist, sectionIndex]() {
        qDebug() << "Artist clicked:" << artist.name() << "service:" << artist.service() << "id:" << artist.id();
        
        if (sectionIndex >= 0) {
            // New UI: use section-based selection
            onArtistSelected(sectionIndex, artist);
        } else {
            // Legacy: old behavior (shouldn't happen in new UI)
            m_currentArtist = artist;
            m_statusLabel->setText(QString("Загрузка постов: %1").arg(artist.name()));
            
            // Проверяем кэш постов
            if (m_cacheManager->hasCachedArtistPosts(artist.service(), artist.id())) {
                qDebug() << "Loading posts from cache for artist:" << artist.id();
                QList<QJsonObject> cachedPosts = m_cacheManager->loadArtistPosts(artist.service(), artist.id());
                if (!cachedPosts.isEmpty()) {
                    // Конвертируем JSON в Post объекты
                    QList<Post> posts;
                    for (const QJsonObject& obj : cachedPosts) {
                        Post post = m_parser->parsePostFromJsonPublic(obj);
                        posts.append(post);
                    }
                    onPostsFound(posts);
                    return;
                }
            }
            
            // Если кэша нет, загружаем с сервера
            updateArtistPosts(artist);
        }
    }));
    
    layout->addWidget(artistWidget, row, col, 1, 1);
}

void MainWindow::onPostsFound(const QList<Post>& posts)
{
    qDebug() << "onPostsFound called with" << posts.size() << "posts";
    m_posts = posts;
    m_statusLabel->setText(QString("Найдено постов: %1").arg(posts.size()));
    
    // This method is kept for compatibility but posts are now displayed via PostViewer
    // when a post is opened from the section-based UI
}

void MainWindow::onAllArtistPostsLoaded(const QList<Post>& posts, const Artist& artist)
{
    try {
        qDebug() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Starting, posts count:" << posts.size() << "artist:" << artist.name();
        
        if (!m_cacheManager) {
            qCritical() << "[ERROR_HANDLER] onAllArtistPostsLoaded: m_cacheManager is null!";
            return;
        }
        
        // Сохраняем посты в кэш
        qDebug() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Saving posts to cache...";
        QList<QJsonObject> postsJson;
        for (int i = 0; i < posts.size(); ++i) {
            try {
                const Post& post = posts[i];
                QJsonObject obj;
                obj["id"] = post.id();
                obj["title"] = post.title();
                obj["content"] = post.content();
                obj["published"] = post.published();
                obj["edited"] = post.edited();
                obj["user"] = post.author();
                obj["service"] = post.service();
                obj["url"] = post.url();
                obj["thumbnail"] = post.thumbnail();
                
                // Сохраняем files, attachments, embeds
                QJsonArray filesArray;
                for (const QVariantMap& file : post.files()) {
                    QJsonObject fileObj;
                    for (auto it = file.begin(); it != file.end(); ++it) {
                        fileObj[it.key()] = QJsonValue::fromVariant(it.value());
                    }
                    filesArray.append(fileObj);
                }
                if (!filesArray.isEmpty()) {
                    obj["file"] = filesArray[0].toObject();
                }
                
                QJsonArray attachmentsArray;
                for (const QVariantMap& att : post.attachments()) {
                    QJsonObject attObj;
                    for (auto it = att.begin(); it != att.end(); ++it) {
                        attObj[it.key()] = QJsonValue::fromVariant(it.value());
                    }
                    attachmentsArray.append(attObj);
                }
                obj["attachments"] = attachmentsArray;
                
                postsJson.append(obj);
            } catch (const std::exception& e) {
                qCritical() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Error processing post" << i << ":" << e.what();
            } catch (...) {
                qCritical() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Unknown error processing post" << i;
            }
        }
        
        qDebug() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Saving" << postsJson.size() << "posts to cache...";
        m_cacheManager->saveArtistPosts(artist.service(), artist.id(), postsJson);
        qDebug() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Posts saved to cache";
        
        // Отображаем посты
        m_posts = posts;
        if (m_statusLabel) {
            m_statusLabel->setText(QString("Загружено %1 постов для %2").arg(posts.size()).arg(artist.name()));
        }
        
        qDebug() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Updating section states, count:" << m_sectionStates.size();
        // Update section state if artist matches current section
        for (int i = 0; i < m_sectionStates.size(); ++i) {
            try {
                if (m_sectionStates[i].selectedArtist.id() == artist.id() && 
                    m_sectionStates[i].selectedArtist.service() == artist.service()) {
                    qDebug() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Found matching section" << i;
                    m_sectionStates[i].artistPosts = posts;
                    // Display posts in the section
                    if (m_sectionStates[i].currentTab == 1) { // Posts tab
                        qDebug() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Displaying posts in section" << i;
                        displayPostsInSection(i, posts);
                        qDebug() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Posts displayed successfully";
                    }
                    break;
                }
            } catch (const std::exception& e) {
                qCritical() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Error updating section" << i << ":" << e.what();
            } catch (...) {
                qCritical() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Unknown error updating section" << i;
            }
        }
        
        qDebug() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Completed successfully";
    } catch (const std::exception& e) {
        qCritical() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Exception:" << e.what();
        if (m_statusLabel) {
            m_statusLabel->setText(QString("Ошибка загрузки постов: %1").arg(e.what()));
        }
    } catch (...) {
        qCritical() << "[ERROR_HANDLER] onAllArtistPostsLoaded: Unknown exception";
        if (m_statusLabel) {
            m_statusLabel->setText("Неизвестная ошибка при загрузке постов");
        }
    }
}

// displayPostsWithPagination removed - using displayPostsInSection instead
// This method used old UI components (m_postsLayout, m_postsContainer) that no longer exist

// addPaginationControls removed - pagination is now handled in displayPostsInSection

void MainWindow::onPostLoaded(const Post& post)
{
    qDebug() << "Post loaded:" << post.title();
    
    // Если есть ожидающий пост для открытия, открываем его
    if (m_hasPendingPost && m_pendingPostToOpen.id() == post.id() && 
        m_pendingPostToOpen.service() == post.service() && 
        m_pendingPostToOpen.author() == post.author()) {
        qDebug() << "[ERROR_HANDLER] onPostLoaded: Opening pending post:" << post.title();
        m_hasPendingPost = false;
        PostViewer* viewer = new PostViewer(post, m_cacheManager, this);
        connect(viewer, &PostViewer::openAuthorRequested, this, &MainWindow::onOpenAuthorFromViewer);
        viewer->show();
        return;
    }
    
    // Format post content with HTML (старый код для совместимости)
    QString html = QString("<div style='padding: 10px;'>");
    html += QString("<h2 style='margin-top: 0;'>%1</h2>").arg(post.title());
    
    // Post metadata
    html += QString("<div style='color: #666; font-size: 12px; margin-bottom: 15px;'>");
    html += QString("<p><strong>Автор:</strong> %1</p>").arg(post.author());
    html += QString("<p><strong>Сервис:</strong> %1</p>").arg(post.service());
    if (!post.published().isEmpty()) {
        html += QString("<p><strong>Опубликовано:</strong> %1</p>").arg(post.published());
    }
    if (!post.edited().isEmpty() && post.edited() != post.published()) {
        html += QString("<p><strong>Отредактировано:</strong> %1</p>").arg(post.edited());
    }
    html += "</div>";
    
    // Post content
    if (!post.content().isEmpty()) {
        // Escape HTML and preserve line breaks
        QString escapedContent = post.content();
        escapedContent.replace("&", "&amp;");
        escapedContent.replace("<", "&lt;");
        escapedContent.replace(">", "&gt;");
        escapedContent.replace("\n", "<br>");
        html += QString("<div style='line-height: 1.6;'>%1</div>").arg(escapedContent);
    } else {
        html += "<p style='color: #999; font-style: italic;'>Содержимое поста отсутствует</p>";
    }
    
    html += "</div>";
    
    m_postContent->setHtml(html);
    m_statusLabel->setText(QString("Пост загружен: %1").arg(post.title()));
    
    // Load post media
    loadPostMedia(post);
}

void MainWindow::loadPostMedia(const Post& post)
{
    // Clear previous media
    QLayoutItem* item;
    while ((item = m_mediaLayout->takeAt(0)) != nullptr) {
        delete item->widget();
        delete item;
    }
    m_mediaCheckboxes.clear();
    m_currentMedia.clear();
    
    int row = 0;
    int col = 0;
    const int maxCols = 4; // Больше колонок для большего блока медиа
    
    // Helper function to add media item
    auto addMediaItem = [this, &row, &col, maxCols, &post](const QVariantMap& item, const QString& sourceType) {
        QVariantMap mediaItem;
        QString path;
        QString name;
        
        // Получаем path и name в зависимости от типа источника
        if (sourceType == "file") {
            path = item.value("path").toString();
            name = item.value("name").toString();
        } else if (sourceType == "attachment") {
            // Для attachments может быть как path, так и url
            if (item.contains("path")) {
                path = item.value("path").toString();
            } else if (item.contains("url")) {
                path = item.value("url").toString();
            }
            name = item.value("name").toString();
        } else if (sourceType == "embed") {
            // Для embeds обычно используется url
            if (item.contains("url")) {
                path = item.value("url").toString();
            } else if (item.contains("path")) {
                path = item.value("path").toString();
            }
            name = item.value("name").toString();
            if (name.isEmpty() && item.contains("subject")) {
                name = item.value("subject").toString();
            }
        }
        
        if (path.isEmpty()) {
            return; // Пропускаем элементы без пути/URL
        }
        
        // Формируем полный URL для медиа файла
        QString fullUrl;
        if (path.startsWith("http://") || path.startsWith("https://")) {
            fullUrl = path;
        } else if (path.startsWith("/")) {
            // Относительный путь от корня сайта
            fullUrl = QString("https://kemono.cr%1").arg(path);
        } else {
            // Относительный путь
            fullUrl = QString("https://kemono.cr/%1").arg(path);
        }
        mediaItem["url"] = fullUrl;
        mediaItem["filename"] = name;
        if (mediaItem["filename"].toString().isEmpty()) {
            // Извлекаем имя файла из пути
            QString pathStr = path;
            int lastSlash = pathStr.lastIndexOf('/');
            if (lastSlash >= 0 && lastSlash < pathStr.length() - 1) {
                mediaItem["filename"] = pathStr.mid(lastSlash + 1);
            } else {
                mediaItem["filename"] = pathStr;
            }
        }
        mediaItem["post_id"] = post.id();
        mediaItem["post_title"] = post.title();
        // Добавляем информацию об авторе для правильного пути сохранения
        if (!m_currentArtist.id().isEmpty()) {
            QString authorName = QString("%1_%2_%3")
                .arg(m_currentArtist.service())
                .arg(m_currentArtist.name())
                .arg(m_currentArtist.id());
            mediaItem["author_name"] = authorName;
        }
        
        // Добавляем превью, если есть
        QString previewPath = path;
        if (previewPath.startsWith("/")) {
            mediaItem["preview_url"] = QString("https://kemono.cr%1").arg(previewPath);
        } else if (!previewPath.startsWith("http://") && !previewPath.startsWith("https://")) {
            mediaItem["preview_url"] = QString("https://kemono.cr/%1").arg(previewPath);
        } else {
            mediaItem["preview_url"] = previewPath;
        }
        
        m_currentMedia.append(mediaItem);
        
        // Create media item widget with preview
        QWidget* mediaWidget = new QWidget(m_mediaContainer);
        QVBoxLayout* mediaLayout = new QVBoxLayout(mediaWidget);
        mediaLayout->setContentsMargins(5, 5, 5, 5);
        
        // Preview image (увеличенный размер)
        QLabel* previewLabel = new QLabel(mediaWidget);
        previewLabel->setMinimumWidth(200);
        previewLabel->setMaximumWidth(200);
        previewLabel->setAlignment(Qt::AlignCenter);
        previewLabel->setScaledContents(false); // Отключаем растягивание для сохранения соотношения сторон
        previewLabel->setStyleSheet(
            "QLabel {"
            "  border: 1px solid #e0e0e0;"
            "  border-radius: 8px;"
            "  background-color: #f8f9fa;"
            "}"
        );
        previewLabel->setText("Загрузка...");
        
        // Load preview asynchronously - используем url самого медиа, а не preview_url
        QString mediaUrl = mediaItem["url"].toString();
        QString filename = mediaItem["filename"].toString();
        if (!mediaUrl.isEmpty()) {
            loadMediaPreview(previewLabel, mediaUrl, filename);
        } else {
            previewLabel->setText("Нет превью");
        }
        mediaLayout->addWidget(previewLabel);
        
        // Filename label
        QLabel* filenameLabel = new QLabel(mediaItem["filename"].toString(), mediaWidget);
        filenameLabel->setWordWrap(true);
        filenameLabel->setStyleSheet("font-size: 10px;");
        mediaLayout->addWidget(filenameLabel);
        
        // Checkbox and view button
        QHBoxLayout* buttonsLayout = new QHBoxLayout();
        QCheckBox* checkbox = new QCheckBox("Выбрать", mediaWidget);
        m_mediaCheckboxes.append(checkbox);
        buttonsLayout->addWidget(checkbox);
        
        QPushButton* viewButton = new QPushButton("Просмотр", mediaWidget);
        viewButton->setStyleSheet(
            "QPushButton {"
            "  background-color: #2c3e50;"
            "  color: white;"
            "  border: none;"
            "  padding: 5px 10px;"
            "  border-radius: 3px;"
            "  font-size: 10px;"
            "}"
            "QPushButton:hover {"
            "  background-color: #1a252f;"
            "}"
        );
        connect(viewButton, &QPushButton::clicked, [this, mediaItem]() {
            qDebug() << "Opening media viewer, URL:" << mediaItem["url"].toString();
            onOpenMediaViewer(mediaItem);
        });
        buttonsLayout->addWidget(viewButton);
        mediaLayout->addLayout(buttonsLayout);
        
        // Style media widget with modern design
        mediaWidget->setStyleSheet(
            "QWidget {"
            "  border: 1px solid #e0e0e0;"
            "  border-radius: 10px;"
            "  background-color: white;"
            "  padding: 6px;"
            "}"
            "QWidget:hover {"
            "  border-color: #2c3e50;"
            "  background-color: #f5f8fa;"
            "}"
        );
        
        m_mediaLayout->addWidget(mediaWidget, row, col);
        
        col += 2;
        if (col >= maxCols * 2) {
            col = 0;
            row++;
        }
    };
    
    // Add attachments first
    QList<QVariantMap> attachments = post.attachments();
    for (const QVariantMap& attachment : attachments) {
        addMediaItem(attachment, "attachment");
    }
    
    // Add files from post
    QList<QVariantMap> files = post.files();
    for (const QVariantMap& file : files) {
        addMediaItem(file, "file");
    }
    
    // Add embeds (if they contain media)
    QList<QVariantMap> embeds = post.embeds();
    for (const QVariantMap& embed : embeds) {
        // Добавляем embed только если у него есть URL или path
        if (embed.contains("url") || embed.contains("path")) {
            addMediaItem(embed, "embed");
        }
    }
}

void MainWindow::onError(const QString& error)
{
    qDebug() << "Error received:" << error;
    m_statusLabel->setText(QString("Ошибка: %1").arg(error));
    QMessageBox::warning(this, "Ошибка", error);
}

void MainWindow::onOpenAuthorFromViewer(const QString& service, const QString& userId, const QString& authorName)
{
    // Try to find artist in cached artists to get real name
    Artist artist;
    artist.setId(userId);
    artist.setService(service);
    
    // Search in cached artists for real name
    // This is called from UI thread, but m_allCachedArtists can be modified from network thread
    // So we need to copy the list first
    QString realName = authorName;
    QList<Artist> cachedArtists;
    {
        LOCK_READ(ArtistsList);
        cachedArtists = m_allCachedArtists;
    }
    for (const Artist& cached : cachedArtists) {
        if (cached.id() == userId && cached.service() == service) {
            realName = cached.name();
            artist = cached; // Use full cached artist data
            break;
        }
    }
    
    // If not found in cache, use provided name or ID
    if (artist.name().isEmpty()) {
        artist.setName(realName.isEmpty() ? userId : realName);
    }
    
    // Use section 0 (Search) for displaying
    int sectionIndex = 0;
    
    // Switch to section visually (this updates sidebar highlighting and shows the section)
    switchToSection(sectionIndex, 1); // 1 = Posts tab
    
    // Call onArtistSelected which handles everything: history, loading, UI
    onArtistSelected(sectionIndex, artist);
}

// Old UI event handlers removed - using new sidebar-based UI

void MainWindow::onOpenMediaViewer(const QVariantMap& mediaItem)
{
    QList<QVariantMap> singleItem;
    singleItem.append(mediaItem);
    MediaViewer* viewer = new MediaViewer(singleItem, 0, m_cacheManager, this);
    viewer->show();
}

// Helper function to create circular avatar
static QPixmap createCircularAvatar(const QPixmap& source, int size)
{
    // Scale source to fill the circle (crop to square first)
    QPixmap scaled;
    if (source.width() != source.height()) {
        int minSide = qMin(source.width(), source.height());
        int x = (source.width() - minSide) / 2;
        int y = (source.height() - minSide) / 2;
        QPixmap cropped = source.copy(x, y, minSide, minSide);
        scaled = cropped.scaled(size, size, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
    } else {
        scaled = source.scaled(size, size, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
    }
    
    // Create circular mask
    QPixmap result(size, size);
    result.fill(Qt::transparent);
    
    QPainter painter(&result);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    
    QPainterPath path;
    path.addEllipse(0, 0, size, size);
    painter.setClipPath(path);
    painter.drawPixmap(0, 0, scaled);
    
    return result;
}

void MainWindow::loadArtistAvatar(QLabel* label, const QString& avatarUrl)
{
    if (!label || avatarUrl.isEmpty()) {
        if (label) label->setText("?");
        return;
    }

    QString normalizedUrl = avatarUrl;
    if (normalizedUrl.startsWith("//")) {
        normalizedUrl.prepend("https:");
    } else if (!normalizedUrl.startsWith("http://") && !normalizedUrl.startsWith("https://")) {
        if (normalizedUrl.startsWith("/")) {
            normalizedUrl = QString("https://img.kemono.cr%1").arg(normalizedUrl);
        } else {
            normalizedUrl = QString("https://img.kemono.cr/%1").arg(normalizedUrl);
        }
    }
    normalizedUrl.replace("img.kemono.su", "img.kemono.cr");
    normalizedUrl.replace("kemono.su", "kemono.cr");

    QString cachedPath = m_cacheManager->getCachedPreviewPath(normalizedUrl);
    if (!cachedPath.isEmpty() && QFile::exists(cachedPath)) {
        QPixmap pixmap(cachedPath);
        if (!pixmap.isNull()) {
            label->setPixmap(createCircularAvatar(pixmap, 80));
            return;
        }
    }

    // Используем MediaDownloadManager для синхронизации загрузок
    PreviewDownloadInfo info;
    info.label = label;
    info.progressBar = nullptr;
    info.width = 80;
    info.height = 80;
    info.type = PreviewType_Avatar;
    m_previewDownloads[normalizedUrl] = info;
    
    QString cachePath = cachedPath;
    if (cachePath.isEmpty()) {
        // Создаем путь для кэша на основе URL (используем тот же механизм, что и CacheManager)
        QString hash = QString::number(qHash(normalizedUrl));
        cachePath = QString("cache/media_previews/%1.png").arg(hash);
    }
    
    MediaDownloadManager* manager = MediaDownloadManager::instance();
    manager->startDownload(normalizedUrl, cachePath, this);
}

void MainWindow::loadArtistBanner(QLabel* label, const QString& bannerUrl)
{
    if (!label || bannerUrl.isEmpty()) {
        return; // Keep gradient background
    }

    QString normalizedUrl = bannerUrl;
    if (normalizedUrl.startsWith("//")) {
        normalizedUrl.prepend("https:");
    }
    normalizedUrl.replace("img.kemono.su", "img.kemono.cr");
    normalizedUrl.replace("kemono.su", "kemono.cr");

    QString cachedPath = m_cacheManager->getCachedPreviewPath(normalizedUrl);
    if (!cachedPath.isEmpty() && QFile::exists(cachedPath)) {
        QPixmap pixmap(cachedPath);
        if (!pixmap.isNull()) {
            label->setPixmap(pixmap.scaled(label->width(), label->height(), Qt::KeepAspectRatioByExpanding, Qt::FastTransformation));
            return;
        }
    }

    // Используем MediaDownloadManager для синхронизации загрузок
    PreviewDownloadInfo info;
    info.label = label;
    info.progressBar = nullptr;
    info.width = label->width();
    info.height = label->height();
    info.type = PreviewType_Banner;
    m_previewDownloads[normalizedUrl] = info;
    
    QString cachePath = m_cacheManager->getCachedPreviewPath(normalizedUrl);
    if (cachePath.isEmpty()) {
        // Создаем путь для кэша на основе URL
        QString hash = QString::number(qHash(normalizedUrl));
        cachePath = QString("cache/media_previews/%1.png").arg(hash);
    }
    
    MediaDownloadManager* manager = MediaDownloadManager::instance();
    manager->startDownload(normalizedUrl, cachePath, this);
}

void MainWindow::loadPostThumbnail(QLabel* label, const QString& thumbnailUrl)
{
    if (!label || thumbnailUrl.isEmpty()) {
        if (label) label->setText("Нет превью");
        return;
    }
    
    QString cachedPath = m_cacheManager->getCachedPreviewPath(thumbnailUrl);
    if (!cachedPath.isEmpty() && QFile::exists(cachedPath)) {
        QPixmap pixmap(cachedPath);
        if (!pixmap.isNull()) {
            label->setPixmap(pixmap.scaled(200, 150, Qt::KeepAspectRatio, Qt::FastTransformation));
            return;
        }
    }
    
    QString fullUrl = thumbnailUrl;
    if (!fullUrl.startsWith("http://") && !fullUrl.startsWith("https://")) {
        fullUrl = fullUrl.startsWith("/") 
            ? QString("https://kemono.cr%1").arg(fullUrl)
            : QString("https://kemono.cr/%1").arg(fullUrl);
    }
    
    // Используем MediaDownloadManager для синхронизации загрузок
    PreviewDownloadInfo info;
    info.label = label;
    info.progressBar = nullptr;
    info.width = 200;
    info.height = 150;
    info.type = PreviewType_Thumbnail;
    m_previewDownloads[fullUrl] = info;
    
    QString cachePath = m_cacheManager->getCachedPreviewPath(fullUrl);
    if (cachePath.isEmpty()) {
        // Создаем путь для кэша на основе URL
        QString hash = QString::number(qHash(fullUrl));
        cachePath = QString("cache/media_previews/%1.png").arg(hash);
    }
    
    MediaDownloadManager* manager = MediaDownloadManager::instance();
    manager->startDownload(fullUrl, cachePath, this);
}

void MainWindow::loadPostThumbnailLarge(QLabel* label, const QString& thumbnailUrl, int width, int height)
{
    if (!label || thumbnailUrl.isEmpty()) {
        if (label) label->setText("Нет превью");
        return;
    }
    
    QString cachedPath = m_cacheManager->getCachedPreviewPath(thumbnailUrl);
    if (!cachedPath.isEmpty() && QFile::exists(cachedPath)) {
        QPixmap pixmap(cachedPath);
        if (!pixmap.isNull()) {
            label->setPixmap(pixmap.scaled(width, height, Qt::KeepAspectRatio, Qt::FastTransformation));
            return;
        }
    }
    
    QString fullUrl = thumbnailUrl;
    if (!fullUrl.startsWith("http://") && !fullUrl.startsWith("https://")) {
        fullUrl = fullUrl.startsWith("/") 
            ? QString("https://kemono.cr%1").arg(fullUrl)
            : QString("https://kemono.cr/%1").arg(fullUrl);
    }
    
    // Используем MediaDownloadManager для синхронизации загрузок
    PreviewDownloadInfo info;
    info.label = label;
    info.progressBar = nullptr;
    info.width = width;
    info.height = height;
    info.type = PreviewType_ThumbnailLarge;
    m_previewDownloads[fullUrl] = info;
    
    QString cachePath = m_cacheManager->getCachedPreviewPath(fullUrl);
    if (cachePath.isEmpty()) {
        // Создаем путь для кэша на основе URL
        QString hash = QString::number(qHash(fullUrl));
        cachePath = QString("cache/media_previews/%1.png").arg(hash);
    }
    
    MediaDownloadManager* manager = MediaDownloadManager::instance();
    manager->startDownload(fullUrl, cachePath, this);
}

// Helper function to round all corners of a pixmap
static QPixmap roundAllCornersPixmap(const QPixmap& src, int radius) {
    if (src.isNull()) return src;
    
    QPixmap result(src.size());
    result.fill(Qt::transparent);
    
    QPainter painter(&result);
    painter.setRenderHint(QPainter::Antialiasing, true);
    painter.setRenderHint(QPainter::SmoothPixmapTransform, true);
    
    QPainterPath path;
    path.addRoundedRect(QRectF(0, 0, src.width(), src.height()), radius, radius);
    
    painter.setClipPath(path);
    painter.drawPixmap(0, 0, src);
    
    return result;
}

void MainWindow::queueThumbnailDownload(QLabel* label, QProgressBar* progressBar, const QString& url, int width, int height)
{
    if (!label || url.isEmpty()) {
        if (label) label->setText("Нет превью");
        return;
    }
    
    QString fullUrl = url;
    if (!fullUrl.startsWith("http://") && !fullUrl.startsWith("https://")) {
        fullUrl = fullUrl.startsWith("/") 
            ? QString("https://kemono.cr%1").arg(fullUrl)
            : QString("https://kemono.cr/%1").arg(fullUrl);
    }
    
    // Check cache first
    QString cachedPath = m_cacheManager->getCachedPreviewPath(fullUrl);
    if (!cachedPath.isEmpty() && QFile::exists(cachedPath)) {
        QPixmap pixmap(cachedPath);
        if (!pixmap.isNull()) {
            QPixmap scaled = pixmap.scaled(width, height, Qt::KeepAspectRatio, Qt::FastTransformation);
            label->setPixmap(roundAllCornersPixmap(scaled, 12));
            if (progressBar) progressBar->hide();
            return;
        }
    }
    
    // Check if already downloading
    {
        LOCK_MUTEX(ThumbnailQueue);
        if (m_thumbnailLabels.contains(fullUrl)) {
            return;
        }
        
        // Add to queue
        ThumbnailQueueItem item;
        item.url = fullUrl;
        item.previewLabel = label;
        item.progressBar = progressBar;
        item.width = width;
        item.height = height;
        
        m_thumbnailQueue.enqueue(item);
        m_thumbnailLabels[fullUrl] = label;
        m_thumbnailProgressBars[fullUrl] = progressBar;
    }
    
    label->setText("В очереди...");
    
    processThumbnailQueue();
}

void MainWindow::processThumbnailQueue()
{
    // Process all queue items immediately without limit
    while (true) {
        ThumbnailQueueItem item;
        {
            LOCK_MUTEX(ThumbnailQueue);
            if (m_thumbnailQueue.isEmpty()) {
                break;
            }
            item = m_thumbnailQueue.dequeue();
            // Skip if label was deleted
            if (!item.previewLabel) {
                continue;
            }
        }
        // Download outside of lock
        downloadThumbnail(item.url, item.previewLabel, item.progressBar, item.width, item.height);
    }
}

void MainWindow::downloadThumbnail(const QString& url, QLabel* label, QProgressBar* progressBar, int width, int height)
{
    // Check if label is still valid before starting download
    if (!label) {
        onThumbnailDownloadFinished(url);
        return;
    }
    
    // Больше не отслеживаем количество активных загрузок
    
    QNetworkRequest request;
    request.setUrl(QUrl(url));
    request.setRawHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
    request.setRawHeader("Referer", "https://kemono.cr/");
    request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
    
    QNetworkReply* reply = m_mediaNetworkManager->get(request);
    if (!reply) {
        if (label) label->setText("Ошибка");
        onThumbnailDownloadFinished(url);
        return;
    }
    
    {
        LOCK_MUTEX(ThumbnailQueue);
        m_activeThumbnailReplies.append(reply);
    }
    
    QPointer<QLabel> safeLabel = label;
    QPointer<QProgressBar> safeProgressBar = progressBar;
    QPointer<MainWindow> safeThis = this;
    
    if (safeLabel) {
        safeLabel->setText("Загрузка...");
    }
    
    if (safeProgressBar) {
        safeProgressBar->show();
        connect(reply, &QNetworkReply::downloadProgress, this, [safeProgressBar](qint64 bytesReceived, qint64 bytesTotal) {
            if (safeProgressBar && bytesTotal > 0) {
                int percent = static_cast<int>((bytesReceived * 100) / bytesTotal);
                safeProgressBar->setValue(percent);
            }
        });
    }
    
    connect(reply, &QNetworkReply::finished, this, [safeThis, safeLabel, safeProgressBar, reply, url, width, height]() {
        if (!safeThis) {
            reply->deleteLater();
            return;
        }
        
        {
            LOCK_MUTEX(ThumbnailQueue);
            safeThis->m_activeThumbnailReplies.removeOne(reply);
        }
        
        // Check if request was aborted (queue cleared)
        if (reply->error() == QNetworkReply::OperationCanceledError) {
            reply->deleteLater();
            return;
        }
        
        bool success = false;
        
        if (reply->error() == QNetworkReply::NoError && safeLabel) {
            QByteArray data = reply->readAll();
            QPixmap pixmap;
            if (pixmap.loadFromData(data)) {
                safeThis->m_cacheManager->cachePreview(url, pixmap);
                QPixmap scaled = pixmap.scaled(width, height, Qt::KeepAspectRatio, Qt::FastTransformation);
                safeLabel->setPixmap(roundAllCornersPixmap(scaled, 12));
                success = true;
                
                if (safeProgressBar) {
                    safeProgressBar->hide();
                }
            }
        }
        
        if (!success && safeLabel) {
            if (safeProgressBar) {
                safeProgressBar->hide();
            }
            safeLabel->setText("");
            
            // Add retry button
            QPushButton* retryBtn = new QPushButton("Повторить", safeLabel);
            retryBtn->setGeometry((width - 100) / 2, (height - 35) / 2, 100, 35);
            retryBtn->setStyleSheet(
                "QPushButton {"
                "  background-color: #dc3545;"
                "  color: white;"
                "  border: none;"
                "  border-radius: 6px;"
                "  font-size: 13px;"
                "}"
                "QPushButton:hover {"
                "  background-color: #c82333;"
                "}"
            );
            retryBtn->show();
            
            QObject::connect(retryBtn, &QPushButton::clicked, [safeThis, url, safeLabel, safeProgressBar, width, height, retryBtn]() {
                if (safeThis && safeLabel) {
                    retryBtn->deleteLater();
                    safeLabel->setText("Загрузка...");
                    if (safeProgressBar) {
                        safeProgressBar->setValue(0);
                        safeProgressBar->show();
                    }
                    safeThis->queueThumbnailDownload(safeLabel, safeProgressBar, url, width, height);
                }
            });
        }
        
        safeThis->onThumbnailDownloadFinished(url);
        reply->deleteLater();
    });
}

void MainWindow::onThumbnailDownloadFinished(const QString& url)
{
    {
        LOCK_MUTEX(ThumbnailQueue);
        m_thumbnailLabels.remove(url);
        m_thumbnailProgressBars.remove(url);
    }
    
    // Больше не нужно обрабатывать очередь - все загрузки запускаются сразу
}

void MainWindow::clearThumbnailQueue()
{
    QList<QNetworkReply*> repliesToAbort;
    {
        LOCK_MUTEX(ThumbnailQueue);
        // Clear the queue
        m_thumbnailQueue.clear();
        
        // Abort all active downloads (they will clean up in their finished callback)
        repliesToAbort = m_activeThumbnailReplies;
        m_activeThumbnailReplies.clear();
        
        // Clear tracking maps
        m_thumbnailLabels.clear();
        m_thumbnailProgressBars.clear();
    }
    
    // Abort replies outside of lock (abort is safe to call from any thread)
    for (QNetworkReply* reply : repliesToAbort) {
        if (reply) {
            reply->abort();
        }
    }
}

void MainWindow::cleanupMemory()
{
    // Clear search results that are no longer needed
    m_allSearchArtists.clear();
    m_allSearchArtists.squeeze();
    
    // Clear media preview tracking
    m_mediaPreviewReplies.clear();
    m_mediaPreviewUrls.clear();
    m_processingLabels.clear();
    m_thumbnailRetryInfo.clear();
    
    // Force garbage collection for QPixmap cache
    QPixmapCache::clear();
}

void MainWindow::clearOtherSectionsData(int currentSection)
{
    // Clear posts data from other sections to free memory
    // UI operations are always in main thread, no locks needed
    for (int i = 0; i < m_sectionStates.size(); ++i) {
        if (i != currentSection) {
            // Keep selected artist info but clear heavy post data
            m_sectionStates[i].artistPosts.clear();
            m_sectionStates[i].artistPosts.squeeze();
        }
    }
}

void MainWindow::showThumbnailRetryButton(QLabel* label, const QString& thumbnailUrl)
{
    if (!label) return;
    
    // Сохраняем информацию для повторной попытки
    m_thumbnailRetryInfo[label] = thumbnailUrl;
    
    // Ищем родительский виджет поста
    QWidget* postWidget = qobject_cast<QWidget*>(label->parent());
    if (!postWidget) return;
    
    QVBoxLayout* postLayout = qobject_cast<QVBoxLayout*>(postWidget->layout());
    if (!postLayout) return;
    
    // Проверяем, есть ли уже кнопка "Повторить"
    bool hasRetryButton = false;
    for (int i = 0; i < postLayout->count(); ++i) {
        QLayoutItem* item = postLayout->itemAt(i);
        if (item && item->widget()) {
            QPushButton* btn = qobject_cast<QPushButton*>(item->widget());
            if (btn && btn->property("retryButton").toBool()) {
                hasRetryButton = true;
                break;
            }
        }
    }
    
    // Добавляем кнопку "Повторить" если её нет
    if (!hasRetryButton) {
        QPushButton* retryBtn = new QPushButton("Повторить", postWidget);
        retryBtn->setProperty("retryButton", true);
        retryBtn->setStyleSheet(
            "QPushButton {"
            "  background-color: #ffc107;"
            "  color: #000;"
            "  border: none;"
            "  padding: 4px 8px;"
            "  border-radius: 3px;"
            "  font-size: 10px;"
            "}"
            "QPushButton:hover {"
            "  background-color: #ffb300;"
            "}"
        );
        connect(retryBtn, &QPushButton::clicked, [this, label, retryBtn]() {
            onThumbnailRetryClicked();
            // Удаляем кнопку после клика
            if (retryBtn && retryBtn->parentWidget()) {
                QVBoxLayout* layout = qobject_cast<QVBoxLayout*>(retryBtn->parentWidget()->layout());
                if (layout) {
                    layout->removeWidget(retryBtn);
                    retryBtn->deleteLater();
                }
            }
        });
        // Вставляем кнопку после thumbnail label (обычно первый виджет)
        postLayout->insertWidget(1, retryBtn);
    }
}

void MainWindow::onThumbnailRetryClicked()
{
    QPushButton* retryBtn = qobject_cast<QPushButton*>(sender());
    if (!retryBtn) return;
    
    // Находим соответствующий label через parent widget
    QWidget* postWidget = qobject_cast<QWidget*>(retryBtn->parent());
    if (!postWidget) return;
    
    QVBoxLayout* layout = qobject_cast<QVBoxLayout*>(postWidget->layout());
    if (!layout) return;
    
    // Ищем label с превью (обычно первый виджет)
    QLabel* label = nullptr;
    for (int i = 0; i < layout->count(); ++i) {
        QLayoutItem* item = layout->itemAt(i);
        if (item && item->widget()) {
            QLabel* candidate = qobject_cast<QLabel*>(item->widget());
            if (candidate && m_thumbnailRetryInfo.contains(candidate)) {
                label = candidate;
                break;
            }
        }
    }
    
    if (!label || !m_thumbnailRetryInfo.contains(label)) {
        qDebug() << "[ERROR_HANDLER] onThumbnailRetryClicked: label not found in retry info";
        return;
    }
    
    // Получаем сохраненный URL
    QString thumbnailUrl = m_thumbnailRetryInfo[label];
    
    // Сбрасываем label
    label->clear();
    label->setText("Загрузка...");
    label->setPixmap(QPixmap());
    label->setStyleSheet(
        "QLabel {"
        "  border: 1px solid #e0e0e0;"
        "  border-radius: 6px;"
        "  background-color: #f5f5f5;"
        "}"
    );
    
    // Повторно загружаем превью
    loadPostThumbnail(label, thumbnailUrl);
}

void MainWindow::loadMediaPreview(QLabel* label, const QString& mediaUrl, const QString& filename)
{
    try {
        if (!label) {
            qCritical() << "[ERROR_HANDLER] loadMediaPreview: label is null";
            return;
        }
        
        if (mediaUrl.isEmpty()) {
            label->setText("Нет превью");
            return;
        }
        
        if (!m_cacheManager) {
            qCritical() << "[ERROR_HANDLER] loadMediaPreview: m_cacheManager is null";
            label->setText("Ошибка");
            return;
        }
        
        // Формируем полный URL сразу
        QString fullUrl = mediaUrl;
        if (!fullUrl.startsWith("http://") && !fullUrl.startsWith("https://")) {
            if (fullUrl.startsWith("/")) {
                fullUrl = QString("https://kemono.cr%1").arg(fullUrl);
            } else {
                fullUrl = QString("https://kemono.cr/%1").arg(fullUrl);
            }
        }
        
        qDebug() << "[ERROR_HANDLER] loadMediaPreview: filename=" << filename << "fullUrl=" << fullUrl;
        
        // Проверяем тип файла - загружаем превью только для изображений
        QString fileExt = QFileInfo(filename).suffix().toLower();
        if (fileExt != "jpg" && fileExt != "jpeg" && fileExt != "png" && 
            fileExt != "gif" && fileExt != "webp" && fileExt != "bmp") {
            // Для не-изображений показываем иконку
            label->setText(QString("📄 %1").arg(filename));
            label->setStyleSheet(
                "QLabel {"
                "  border: 1px solid #e0e0e0;"
                "  border-radius: 8px;"
                "  background-color: #f8f9fa;"
                "  color: #666;"
                "  font-size: 11px;"
                "}"
            );
            return;
        }
        
        // Check cache first - используем fullUrl для кэша
        QString cachedPath = m_cacheManager->getCachedPreviewPath(fullUrl);
        if (!cachedPath.isEmpty() && QFile::exists(cachedPath)) {
            try {
                // Загружаем и обрабатываем в фоновом потоке
                QFile file(cachedPath);
                if (file.open(QIODevice::ReadOnly)) {
                    QByteArray data = file.readAll();
                    file.close();
                    
                    if (!m_imageProcessor) {
                        qCritical() << "[ERROR_HANDLER] loadMediaPreview: m_imageProcessor is null";
                        label->setText("Ошибка");
                        return;
                    }
                    
                    // Сохраняем связь для обработки
                    m_processingLabels[fullUrl] = label;
                    
                    // Обрабатываем в фоновом потоке
                    QMetaObject::invokeMethod(m_imageProcessor, "processImage", Qt::QueuedConnection,
                                              Q_ARG(QByteArray, data),
                                              Q_ARG(QString, fullUrl),
                                              Q_ARG(int, 200));
                    qDebug() << "[ERROR_HANDLER] loadMediaPreview: Preview processing from cache for:" << fullUrl;
                    return;
                }
            } catch (const std::exception& e) {
                qCritical() << "[ERROR_HANDLER] loadMediaPreview: Error loading from cache:" << e.what();
            } catch (...) {
                qCritical() << "[ERROR_HANDLER] loadMediaPreview: Unknown error loading from cache";
            }
        }
        
        if (!m_mediaNetworkManager) {
            qCritical() << "[ERROR_HANDLER] loadMediaPreview: m_mediaNetworkManager is null";
            label->setText("Ошибка");
            return;
        }
        
        // Load asynchronously using shared network manager
        QNetworkRequest request;
        request.setUrl(QUrl(fullUrl));
        request.setRawHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
        request.setRawHeader("Referer", "https://kemono.cr/");
        // Отключаем HTTP/2 для избежания ошибок "Server refused a stream"
        request.setAttribute(QNetworkRequest::Http2AllowedAttribute, false);
        
        QNetworkReply* reply = m_mediaNetworkManager->get(request);
        if (!reply) {
            qCritical() << "[ERROR_HANDLER] loadMediaPreview: Failed to create network reply";
            label->setText("Ошибка");
            return;
        }
        
        // Сохраняем связь между reply и label
        m_mediaPreviewReplies[reply] = label;
        m_mediaPreviewUrls[reply] = fullUrl;
        
        // Подключаем сигнал finished к конкретному reply
        connect(reply, &QNetworkReply::finished, this, &MainWindow::onMediaPreviewLoaded);
        
        qDebug() << "[ERROR_HANDLER] loadMediaPreview: Started loading preview for:" << fullUrl;
    } catch (const std::exception& e) {
        qCritical() << "[ERROR_HANDLER] loadMediaPreview: Exception:" << e.what();
        if (label) {
            label->setText("Ошибка");
        }
    } catch (...) {
        qCritical() << "[ERROR_HANDLER] loadMediaPreview: Unknown exception";
        if (label) {
            label->setText("Ошибка");
        }
    }
}

void MainWindow::onMediaPreviewLoaded()
{
    QNetworkReply* reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) {
        qDebug() << "onMediaPreviewLoaded: reply is null";
        return;
    }
    
    // Получаем соответствующий label и URL
    QLabel* label = m_mediaPreviewReplies.value(reply, nullptr);
    QString url = m_mediaPreviewUrls.value(reply, reply->url().toString());
    m_mediaPreviewReplies.remove(reply);
    m_mediaPreviewUrls.remove(reply);
    
    qDebug() << "Media preview loaded for URL:" << url << "error:" << reply->error() << "label:" << label;
    
    // Проверяем, что label все еще существует
    if (!label) {
        qDebug() << "Label is null, skipping update";
        reply->deleteLater();
        return;
    }
    
    // Обрабатываем ответ
    if (reply->error() == QNetworkReply::NoError) {
        QByteArray data = reply->readAll();
        qDebug() << "Received" << data.size() << "bytes for preview";
        
        if (data.isEmpty()) {
            qDebug() << "Empty data received";
            label->setText("Ошибка: пустые данные");
            reply->deleteLater();
            return;
        }
        
        // Сохраняем связь между URL и label для обработки в фоновом потоке
        m_processingLabels[url] = label;
        
        // Сохраняем оригинальное изображение в кэш перед обработкой
        QPixmap originalPixmap;
        if (originalPixmap.loadFromData(data)) {
            m_cacheManager->cachePreview(url, originalPixmap);
        }
        
        // Отправляем данные в фоновый поток для обработки
        QMetaObject::invokeMethod(m_imageProcessor, "processImage", Qt::QueuedConnection,
                                  Q_ARG(QByteArray, data),
                                  Q_ARG(QString, url),
                                  Q_ARG(int, 200));
    } else {
        qDebug() << "Network error:" << reply->error() << reply->errorString();
        label->setText("Ошибка сети");
    }
    
    reply->deleteLater();
}

void MainWindow::onImageProcessed(const QPixmap& scaledPixmap, const QString& url)
{
    try {
        // Находим соответствующий label по URL (может быть как fullUrl, так и thumbnailUrl)
        QLabel* label = m_processingLabels.value(url, nullptr);
        
        // Если не найдено по полному URL, пробуем найти по оригинальному thumbnailUrl
        if (!label) {
            // Ищем по всем ключам, которые могут соответствовать этому URL
            for (auto it = m_processingLabels.begin(); it != m_processingLabels.end(); ++it) {
                QString key = it.key();
                // Проверяем, соответствует ли ключ URL (может быть относительный путь)
                if (key == url || key.endsWith(url) || url.endsWith(key)) {
                    label = it.value();
                    m_processingLabels.remove(key);
                    break;
                }
            }
        } else {
            m_processingLabels.remove(url);
        }
        
        if (!label) {
            qDebug() << "[ERROR_HANDLER] onImageProcessed: Label not found for processed image:" << url;
            return;
        }
        
        // Обновляем label в главном потоке
        // Масштабируем до нужного размера для превью постов
        QPixmap finalPixmap = scaledPixmap;
        if (finalPixmap.width() > 200 || finalPixmap.height() > 150) {
            finalPixmap = scaledPixmap.scaled(200, 150, Qt::KeepAspectRatio, Qt::FastTransformation);
        }
        label->setPixmap(finalPixmap);
        label->setText(""); // Очищаем текст "Загрузка..."
        label->setScaledContents(false); // Отключаем автоматическое растягивание
        qDebug() << "[ERROR_HANDLER] onImageProcessed: Preview pixmap set to label successfully for:" << url;
    } catch (const std::exception& e) {
        qCritical() << "[ERROR_HANDLER] onImageProcessed: Exception:" << e.what();
    } catch (...) {
        qCritical() << "[ERROR_HANDLER] onImageProcessed: Unknown exception";
    }
}

void MainWindow::onImageProcessingFailed(const QString& url)
{
    try {
        // Находим соответствующий label по URL
        QLabel* label = m_processingLabels.value(url, nullptr);
        
        if (label) {
            label->setText("Ошибка загрузки");
            m_processingLabels.remove(url);
        }
        qDebug() << "[ERROR_HANDLER] onImageProcessingFailed: Image processing failed for:" << url;
    } catch (const std::exception& e) {
        qCritical() << "[ERROR_HANDLER] onImageProcessingFailed: Exception:" << e.what();
    } catch (...) {
        qCritical() << "[ERROR_HANDLER] onImageProcessingFailed: Unknown exception";
    }
}

// onLoadArtistPosts and onLoadPostFromUrl removed - using new sidebar-based UI

void MainWindow::setupMenu()
{
    qDebug() << "Setting up menu...";
    m_menuBar = menuBar();
    
    m_fileMenu = m_menuBar->addMenu("Файл");
    QAction* exitAction = m_fileMenu->addAction("Выход");
    connect(exitAction, &QAction::triggered, this, &QMainWindow::close);
    
    m_toolsMenu = m_menuBar->addMenu("Инструменты");
    QAction* clearCacheAction = m_toolsMenu->addAction("Очистить кэш");
    connect(clearCacheAction, &QAction::triggered, [this]() {
        if (m_cacheManager) {
            m_cacheManager->clearCache();
            QMessageBox::information(this, "Кэш", "Кэш очищен");
        }
    });
    qDebug() << "Menu setup complete";
}

// displayPostsInGrid removed - using displayPostsInSection instead

void MainWindow::onArtistItemClicked(QListWidgetItem* item)
{
    Q_UNUSED(item);
    // This method is kept for compatibility but not used in new structure
}

void MainWindow::onPostItemClicked(QListWidgetItem* item)
{
    Q_UNUSED(item);
    // TODO: Implement post item click handler
}

void MainWindow::onDownloadProgress(const QString& url, qint64 bytesReceived, qint64 bytesTotal)
{
    // Реализация IMediaDownloadSubscriber для превью и аватарок
    if (m_previewDownloads.contains(url)) {
        PreviewDownloadInfo& info = m_previewDownloads[url];
        // Проверяем, что виджет еще существует
        if (!info.label) {
            m_previewDownloads.remove(url);
            return;
        }
        if (info.progressBar && bytesTotal > 0) {
            int percent = static_cast<int>((bytesReceived * 100) / bytesTotal);
            info.progressBar->setValue(percent);
            info.progressBar->show();
        }
    }
}

void MainWindow::onDownloadFinished(const QString& url, const QString& filepath, bool success)
{
    // Реализация IMediaDownloadSubscriber для превью и аватарок
    if (!m_previewDownloads.contains(url)) {
        return;
    }
    
    PreviewDownloadInfo info = m_previewDownloads[url];
    m_previewDownloads.remove(url);
    
    // Проверяем, что виджет еще существует (не был удален при переключении страниц)
    if (!info.label) {
        return;
    }
    
    // Виджет проверен выше, продолжаем обработку
    
    if (success && QFile::exists(filepath)) {
        // Сохраняем указатель на label для безопасного доступа
        QPointer<QLabel> safeLabel = info.label;
        QPointer<QProgressBar> safeProgressBar = info.progressBar;
        PreviewType type = info.type;
        int width = info.width;
        int height = info.height;
        QString cacheUrl = url;
        QString filePath = filepath;
        
        // Загружаем и обрабатываем изображение в фоновом потоке
        QFuture<QPixmap> future = QtConcurrent::run([filePath, type, width, height]() -> QPixmap {
            // Загружаем изображение из файла в фоновом потоке
            QPixmap pixmap(filePath);
            if (pixmap.isNull()) {
                return QPixmap();
            }
            
            QPixmap processed;
            
            switch (type) {
                case PreviewType_Avatar:
                    processed = createCircularAvatar(pixmap, 80);
                    break;
                case PreviewType_Banner:
                    // Для баннера используем сохраненные размеры
                    processed = pixmap.scaled(width, height, Qt::KeepAspectRatioByExpanding, Qt::SmoothTransformation);
                    break;
                case PreviewType_Thumbnail:
                    processed = pixmap.scaled(200, 150, Qt::KeepAspectRatio, Qt::SmoothTransformation);
                    break;
                case PreviewType_ThumbnailLarge:
                    processed = pixmap.scaled(width, height, Qt::KeepAspectRatio, Qt::SmoothTransformation);
                    if (width == 350 && height == 300) {
                        processed = roundAllCornersPixmap(processed, 12);
                    }
                    break;
            }
            
            return processed;
        });
        
        // Создаем watcher для отслеживания завершения обработки
        QFutureWatcher<QPixmap>* watcher = new QFutureWatcher<QPixmap>(this);
        connect(watcher, &QFutureWatcher<QPixmap>::finished, this, [safeLabel, safeProgressBar, watcher, cacheUrl, filePath, this]() {
            if (!safeLabel) {
                watcher->deleteLater();
                return;
            }
            
            QPixmap processed = watcher->result();
            if (!processed.isNull()) {
                safeLabel->setPixmap(processed);
                
                // Кэшируем превью (если еще не закэшировано)
                if (!m_cacheManager->getCachedPreviewPath(cacheUrl).isEmpty()) {
                    // Загружаем оригинальное изображение для кэширования
                    QPixmap originalPixmap(filePath);
                    if (!originalPixmap.isNull()) {
                        m_cacheManager->cachePreview(cacheUrl, originalPixmap);
                    }
                }
            } else {
                safeLabel->setText("Ошибка");
            }
            
            if (safeProgressBar) {
                safeProgressBar->hide();
            }
            
            watcher->deleteLater();
        });
        
        watcher->setFuture(future);
    } else {
        // Ошибка загрузки - скрываем прогресс-бар сразу
        if (info.progressBar) {
            info.progressBar->hide();
        }
        
        if (info.type == PreviewType_Avatar) {
            info.label->setText("?");
        } else if (info.type != PreviewType_Banner) {
            // Для баннеров не показываем ошибку, оставляем градиентный фон
            info.label->setText("Ошибка");
        }
        // Для PreviewType_Banner просто не устанавливаем текст - остается градиентный фон
    }
}
