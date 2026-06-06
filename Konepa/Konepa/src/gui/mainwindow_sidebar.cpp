// New sidebar and section setup methods

#include "gui/mainwindow.h"
#include "gui/postviewer.h"
#include "core/lockmanager.h"
#include "core/mediadownloadmanager.h"
#include <QPushButton>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLabel>
#include <QScrollArea>
#include <QGridLayout>
#include <QLineEdit>
#include <QComboBox>
#include <QTimer>
#include <QDebug>
#include <QGraphicsDropShadowEffect>
#include <QRandomGenerator>
#include <QFontMetrics>
#include <QPixmapCache>
#include <algorithm>
#include <QEvent>
#include <functional>

namespace {
    class ResizeEventFilter : public QObject {
    public:
        ResizeEventFilter(QObject* parent, std::function<void()> callback)
            : QObject(parent), m_callback(callback) {}
        
        bool eventFilter(QObject* obj, QEvent* event) override {
            if (event->type() == QEvent::Resize || event->type() == QEvent::Show) {
                if (m_callback) {
                    m_callback();
                }
            }
            return QObject::eventFilter(obj, event);
        }
    
    private:
        std::function<void()> m_callback;
    };
    
    QString findImagePath(const Post& post) {
        // Check attachments first
        QList<QVariantMap> attachments = post.attachments();
        for (const QVariantMap& att : attachments) {
            QString path = att.contains("path") ? att["path"].toString() : att.value("url").toString();
            QString lower = path.toLower();
            if (lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".png") || 
                lower.endsWith(".gif") || lower.endsWith(".webp")) {
                return path;
            }
        }
        // Check files
        QList<QVariantMap> files = post.files();
        for (const QVariantMap& file : files) {
            QString path = file.contains("path") ? file["path"].toString() : file.value("url").toString();
            QString lower = path.toLower();
            if (lower.endsWith(".jpg") || lower.endsWith(".jpeg") || lower.endsWith(".png") || 
                lower.endsWith(".gif") || lower.endsWith(".webp")) {
                return path;
            }
        }
        return QString();
    }
}

void MainWindow::setupSidebar()
{
    m_sidebar = new QWidget(this);
    m_sidebar->setFixedWidth(220);
    m_sidebar->setStyleSheet(R"(
        QWidget#sidebar {
            background: rgba(255, 255, 255, 0.7);
            border-right: 1px solid rgba(0,0,0,0.08);
        }
    )");
    m_sidebar->setObjectName("sidebar");
    
    m_sidebarLayout = new QVBoxLayout(m_sidebar);
    m_sidebarLayout->setContentsMargins(0, 0, 0, 0);
    m_sidebarLayout->setSpacing(0);
    
    // App title - clean macOS style
    QWidget* titleContainer = new QWidget(m_sidebar);
    titleContainer->setStyleSheet("background: transparent;");
    QVBoxLayout* titleLayout = new QVBoxLayout(titleContainer);
    titleLayout->setContentsMargins(16, 20, 16, 16);
    
    QLabel* titleLabel = new QLabel("Konepa", titleContainer);
    titleLabel->setStyleSheet(R"(
        QLabel {
            color: #1d1d1f;
            font-size: 20px;
            font-weight: 700;
            background: transparent;
        }
    )");
    titleLayout->addWidget(titleLabel);
    
    QLabel* subtitleLabel = new QLabel("Kemono Parser", titleContainer);
    subtitleLabel->setStyleSheet(R"(
        QLabel {
            color: rgba(0,0,0,0.45);
            font-size: 11px;
            background: transparent;
        }
    )");
    titleLayout->addWidget(subtitleLabel);
    m_sidebarLayout->addWidget(titleContainer);
    
    // Section buttons - macOS sidebar style
    QStringList sectionNames = {"ПОИСК", "ИСТОРИЯ", "ОФФЛАЙН"};
    m_sidebarButtons.clear();
    
    for (int i = 0; i < 3; ++i) {
        // Section header
        QLabel* sectionLabel = new QLabel(sectionNames[i], m_sidebar);
        sectionLabel->setStyleSheet(R"(
            QLabel {
                color: rgba(0,0,0,0.4);
                font-size: 11px;
                font-weight: 600;
                letter-spacing: 0.5px;
                padding: 16px 16px 6px 16px;
                background: transparent;
            }
        )");
        m_sidebarLayout->addWidget(sectionLabel);
        
        // Section tabs (Авторы, Посты)
        QPushButton* artistsBtn = new QPushButton("Авторы", m_sidebar);
        artistsBtn->setCheckable(true);
        artistsBtn->setProperty("section", i);
        artistsBtn->setProperty("tab", 0);
        artistsBtn->setCursor(Qt::PointingHandCursor);
        artistsBtn->setStyleSheet(R"(
            QPushButton {
                background: transparent;
                color: rgba(0,0,0,0.7);
                border: none;
                border-radius: 6px;
                text-align: left;
                padding: 8px 12px;
                font-size: 13px;
                margin: 1px 8px;
            }
            QPushButton:hover {
                background: rgba(0,0,0,0.05);
            }
            QPushButton:checked {
                background: rgba(0,122,255,0.12);
                color: #007AFF;
                font-weight: 500;
            }
        )");
        
        QPushButton* postsBtn = new QPushButton("Посты", m_sidebar);
        postsBtn->setCheckable(true);
        postsBtn->setProperty("section", i);
        postsBtn->setProperty("tab", 1);
        postsBtn->setCursor(Qt::PointingHandCursor);
        postsBtn->setStyleSheet(artistsBtn->styleSheet());
        
        // Store buttons
        QList<QPushButton*> sectionButtons;
        sectionButtons.append(artistsBtn);
        sectionButtons.append(postsBtn);
        m_sidebarButtons.append(sectionButtons);
        
        connect(artistsBtn, &QPushButton::clicked, [this, i]() {
            m_sectionStates[i].currentTab = 0;
            switchToSection(i, 0);
        });
        
        connect(postsBtn, &QPushButton::clicked, [this, i]() {
            m_sectionStates[i].currentTab = 1;
            switchToSection(i, 1);
        });
        
        m_sidebarLayout->addWidget(artistsBtn);
        m_sidebarLayout->addWidget(postsBtn);
    }
    
    // Set initial highlighting
    updateSidebarHighlighting(0, 0);
    
    m_sidebarLayout->addStretch();
    
    m_mainLayout->addWidget(m_sidebar, 0); // Sidebar fixed width
}

void MainWindow::setupSection(const QString& sectionName, int sectionIndex)
{
    Q_UNUSED(sectionName);
    
    QWidget* sectionWidget = new QWidget();
    sectionWidget->setStyleSheet("background: transparent;");
    QVBoxLayout* sectionLayout = new QVBoxLayout(sectionWidget);
    sectionLayout->setContentsMargins(0, 0, 0, 0);
    sectionLayout->setSpacing(0);
    
    setupArtistsTab(sectionIndex);
    setupPostsTab(sectionIndex);
    
    if (sectionIndex >= m_artistsTabs.size() || sectionIndex >= m_postsTabs.size()) {
        return;
    }
    
    // Show artists tab by default, hide posts tab
    m_artistsTabs[sectionIndex]->setVisible(true);
    m_postsTabs[sectionIndex]->setVisible(false);
    
    // Add both tabs to layout (only one visible at a time) - take full height
    sectionLayout->addWidget(m_artistsTabs[sectionIndex], 1);
    sectionLayout->addWidget(m_postsTabs[sectionIndex], 1);
    
    m_sectionWidgets.append(sectionWidget);
    m_sectionTabs.append(nullptr); // No QTabWidget anymore
}

void MainWindow::setupArtistsTab(int sectionIndex)
{
    QWidget* artistsTab = new QWidget();
    artistsTab->setStyleSheet("background: transparent;");
    QVBoxLayout* artistsLayout = new QVBoxLayout(artistsTab);
    artistsLayout->setContentsMargins(0, 0, 0, 0);
    artistsLayout->setSpacing(0);
    
    // Top overlay with controls and gradient
    QWidget* topOverlay = new QWidget(artistsTab);
    topOverlay->setStyleSheet("background: transparent; margin: 0; padding: 0; border: none;");
    topOverlay->setAttribute(Qt::WA_TransparentForMouseEvents, false);
    
    // Gradient mask widget - container with controls inside (height: 100px)
    QWidget* gradientMask = new QWidget(topOverlay);
    gradientMask->setStyleSheet(R"(
        QWidget {
            background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
                stop:0 rgba(246,246,246,1), stop:1 rgba(246,246,246,0));
            margin: 0;
            padding: 0;
            border: none;
        }
    )");
    gradientMask->setAttribute(Qt::WA_TransparentForMouseEvents, false);
    QVBoxLayout* gradientLayout = new QVBoxLayout(gradientMask);
    gradientLayout->setContentsMargins(0, 0, 0, 0);
    gradientLayout->setSpacing(0);
    
    // Controls container - inside gradient
    QWidget* controlsContainer = new QWidget(gradientMask);
    controlsContainer->setStyleSheet("background: transparent;");
    QVBoxLayout* controlsLayout = new QVBoxLayout(controlsContainer);
    controlsLayout->setContentsMargins(16, 8, 16, 8);
    controlsLayout->setSpacing(8);
    gradientLayout->addWidget(controlsContainer);
    
    // Search panel (only for Поиск section)
    if (sectionIndex == 0) {
        QWidget* searchPanel = new QWidget();
        searchPanel->setStyleSheet("background: transparent;");
        QHBoxLayout* searchLayout = new QHBoxLayout(searchPanel);
        searchLayout->setContentsMargins(0, 0, 0, 0);
        searchLayout->setSpacing(10);
        
        QLineEdit* searchInput = new QLineEdit();
        searchInput->setPlaceholderText("Поиск авторов...");
        searchInput->setMinimumHeight(36);
        searchLayout->addWidget(searchInput, 1);
        
        QComboBox* serviceCombo = new QComboBox();
        serviceCombo->addItems({
            "все сервисы", "patreon", "pixiv fanbox", "discord",
            "fantia", "boosty", "gumroad", "subscribe star", "DLsite"
        });
        serviceCombo->setCurrentText("все сервисы");
        serviceCombo->setMinimumHeight(36);
        searchLayout->addWidget(serviceCombo);
        
        QString primaryBtnStyle = R"(
            QPushButton {
                background: #007AFF;
                color: white;
                padding: 8px 16px;
                border-radius: 8px;
                border: none;
                font-weight: 500;
                font-size: 13px;
            }
            QPushButton:hover {
                background: #0056CC;
            }
        )";
        
        QPushButton* searchBtn = new QPushButton("Искать");
        searchBtn->setMinimumHeight(36);
        searchBtn->setCursor(Qt::PointingHandCursor);
        searchBtn->setStyleSheet(primaryBtnStyle);
        connect(searchBtn, &QPushButton::clicked, [this, sectionIndex, searchInput, serviceCombo]() {
            Q_UNUSED(serviceCombo);
            QString query = searchInput->text().trimmed();
            m_sectionStates[sectionIndex].searchQuery = query;
            
            if (query.isEmpty()) {
                if (!m_allCachedArtists.isEmpty()) {
                    m_sectionStates[sectionIndex].artistsPage = 0;
                    m_sectionStates[sectionIndex].artists = m_allCachedArtists;
                    displayArtistsInSection(sectionIndex, m_allCachedArtists);
                }
            } else {
                performLocalSearch(query, 0);
            }
        });
        searchLayout->addWidget(searchBtn);
        
        QPushButton* refreshBtn = new QPushButton("Обновить");
        refreshBtn->setMinimumHeight(36);
        refreshBtn->setCursor(Qt::PointingHandCursor);
        refreshBtn->setStyleSheet(R"(
            QPushButton {
                background: rgba(0,0,0,0.05);
                color: #1d1d1f;
                padding: 8px 14px;
                border-radius: 8px;
                border: 1px solid rgba(0,0,0,0.1);
                font-weight: 500;
                font-size: 13px;
            }
            QPushButton:hover {
                background: rgba(0,0,0,0.08);
            }
        )");
        connect(refreshBtn, &QPushButton::clicked, [this]() {
            m_statusLabel->setText("Обновление базы данных...");
            m_parser->getAllArtists();
        });
        searchLayout->addWidget(refreshBtn);
        
        m_searchInputs.append(searchInput);
        m_searchButtons.append(searchBtn);
        
        controlsLayout->addWidget(searchPanel);
        
        // Sort and random panel
        QWidget* sortPanel = new QWidget();
        sortPanel->setStyleSheet("background: transparent;");
        QHBoxLayout* sortLayout = new QHBoxLayout(sortPanel);
        sortLayout->setContentsMargins(0, 4, 0, 8);
        sortLayout->setSpacing(10);
        
        QLabel* sortLabel = new QLabel("Сортировка:");
        sortLabel->setStyleSheet("color: rgba(0,0,0,0.5); font-size: 12px;");
        sortLayout->addWidget(sortLabel);
        
        QComboBox* sortCombo = new QComboBox();
        sortCombo->addItems({"Все авторы", "Популярные", "Недавно обновлённые"});
        sortCombo->setMinimumHeight(32);
        connect(sortCombo, QOverload<int>::of(&QComboBox::currentIndexChanged), [this, sectionIndex](int index) {
            m_sectionStates[sectionIndex].artistsPage = 0;
            if (m_allCachedArtists.isEmpty()) {
                m_statusLabel->setText("База авторов пуста. Нажмите 'Обновить базу'");
                return;
            }
            
            QList<Artist> sortedArtists = m_allCachedArtists;
            
            if (index == 0) {
                // Все авторы - без сортировки (по умолчанию)
                m_statusLabel->setText(QString("Все авторы: %1").arg(sortedArtists.size()));
            } else if (index == 1) {
                // Популярные - сортируем по faved (если есть) или по indexed
                std::sort(sortedArtists.begin(), sortedArtists.end(), [](const Artist& a, const Artist& b) {
                    // Сортируем по дате индексации (более старые = более популярные)
                    return a.indexed() < b.indexed();
                });
                m_statusLabel->setText(QString("Популярные авторы: %1").arg(sortedArtists.size()));
            } else if (index == 2) {
                // Недавно обновлённые - сортируем по updated
                std::sort(sortedArtists.begin(), sortedArtists.end(), [](const Artist& a, const Artist& b) {
                    return a.updated() > b.updated(); // Новые первыми
                });
                m_statusLabel->setText(QString("Недавно обновлённые: %1").arg(sortedArtists.size()));
            }
            
            m_sectionStates[sectionIndex].artists = sortedArtists; // Save sorted artists for pagination
            displayArtistsInSection(sectionIndex, sortedArtists);
        });
        sortLayout->addWidget(sortCombo);
        
        sortLayout->addStretch();
        
        QPushButton* randomArtistBtn = new QPushButton("Случайный");
        randomArtistBtn->setMinimumHeight(32);
        randomArtistBtn->setCursor(Qt::PointingHandCursor);
        randomArtistBtn->setStyleSheet(R"(
            QPushButton {
                background: #5856D6;
                color: white;
                padding: 6px 14px;
                border-radius: 8px;
                border: none;
                font-weight: 500;
                font-size: 12px;
            }
            QPushButton:hover {
                background: #4240B0;
            }
        )");
        connect(randomArtistBtn, &QPushButton::clicked, [this]() {
            if (m_allCachedArtists.isEmpty()) {
                m_statusLabel->setText("База авторов пуста. Нажмите 'Обновить базу'");
                return;
            }
            // Выбираем случайного автора из локальной базы
            int randomIndex = QRandomGenerator::global()->bounded(m_allCachedArtists.size());
            Artist randomArtist = m_allCachedArtists[randomIndex];
            m_statusLabel->setText(QString("Случайный автор: %1").arg(randomArtist.name()));
            
            // Добавляем в историю
            if (m_historyManager) {
                m_historyManager->addArtist(randomArtist);
            }
            
            // Открываем посты этого автора
            m_sectionStates[0].selectedArtist = randomArtist;
            m_currentArtist = randomArtist;
            m_sectionStates[0].postsPage = 0;
            // Update author name label
            if (0 < m_authorNameLabels.size() && m_authorNameLabels[0]) {
                m_authorNameLabels[0]->setText(randomArtist.name());
            }
            switchToSection(0, 1);
            m_parser->getAllArtistPosts(randomArtist);
        });
        sortLayout->addWidget(randomArtistBtn);
        
        controlsLayout->addWidget(sortPanel);
    } else {
        m_searchInputs.append(nullptr);
        m_searchButtons.append(nullptr);
    }
    
    // Add top overlay to tab (will be positioned absolutely)
    topOverlay->setParent(artistsTab);
    topOverlay->raise();
    
    // Position gradient (with controls inside) absolutely
    gradientMask->setParent(topOverlay);
    
    // Full-screen scroll area
    QScrollArea* scrollArea = new QScrollArea(artistsTab);
    scrollArea->setWidgetResizable(true);
    scrollArea->setStyleSheet(R"(
        QScrollArea {
            border: none;
            background: transparent;
        }
    )");
    
    QWidget* container = new QWidget();
    container->setStyleSheet("background: transparent;");
    QGridLayout* gridLayout = new QGridLayout(container);
    gridLayout->setSpacing(20);
    gridLayout->setContentsMargins(16, 100, 16, 53); // Top padding for gradient, bottom for gradient
    
    scrollArea->setWidget(container);
    scrollArea->lower(); // Behind overlay
    artistsLayout->addWidget(scrollArea, 1); // Takes remaining space
    
    // Bottom overlay with pagination and gradient
    QWidget* bottomOverlay = new QWidget(artistsTab);
    bottomOverlay->setStyleSheet("background: transparent; margin: 0; padding: 0; border: none;");
    bottomOverlay->setAttribute(Qt::WA_TransparentForMouseEvents, false);
    
    // Gradient mask widget (bottom-up) - container with pagination inside (reduced by one third: ~53px)
    QWidget* bottomGradientMask = new QWidget(bottomOverlay);
    bottomGradientMask->setStyleSheet(R"(
        QWidget {
            background: qlineargradient(x1:0, y1:1, x2:0, y2:0,
                stop:0 rgba(246,246,246,1), stop:1 rgba(246,246,246,0));
            margin: 0;
            padding: 0;
            border: none;
        }
    )");
    bottomGradientMask->setAttribute(Qt::WA_TransparentForMouseEvents, false);
    QVBoxLayout* bottomGradientLayout = new QVBoxLayout(bottomGradientMask);
    bottomGradientLayout->setContentsMargins(0, 0, 0, 0);
    bottomGradientLayout->setSpacing(0);
    
    // Pagination container - inside gradient
    QWidget* paginationContainer = new QWidget(bottomGradientMask);
    paginationContainer->setStyleSheet("background: transparent;");
    QHBoxLayout* paginationLayout = new QHBoxLayout(paginationContainer);
    paginationLayout->setContentsMargins(16, 8, 16, 8);
    paginationLayout->addStretch();
    bottomGradientLayout->addWidget(paginationContainer);
    
    QString paginationBtnStyle = R"(
        QPushButton {
            background: rgba(255,255,255,0.95);
            color: #1d1d1f;
            border: 1px solid rgba(0,0,0,0.1);
            padding: 10px 24px;
            border-radius: 20px;
            font-size: 13px;
            font-weight: 500;
        }
        QPushButton:hover {
            background: #fff;
        }
        QPushButton:disabled {
            color: rgba(0,0,0,0.25);
            background: rgba(255,255,255,0.6);
        }
    )";
    
    QPushButton* prevBtn = new QPushButton("Назад");
    prevBtn->setCursor(Qt::PointingHandCursor);
    prevBtn->setStyleSheet(paginationBtnStyle);
    connect(prevBtn, &QPushButton::clicked, this, [this, sectionIndex]() {
        if (sectionIndex < m_sectionStates.size() && m_sectionStates[sectionIndex].artistsPage > 0) {
            m_sectionStates[sectionIndex].artistsPage--;
            displayArtistsInSection(sectionIndex, m_sectionStates[sectionIndex].artists);
        }
    });
    paginationLayout->addWidget(prevBtn);
    
    QLabel* pageLabel = new QLabel("1 / 1");
    pageLabel->setStyleSheet("color: rgba(0,0,0,0.6); padding: 0 20px; font-size: 13px; font-weight: 500; background: transparent;");
    paginationLayout->addWidget(pageLabel);
    
    QPushButton* nextBtn = new QPushButton("Вперед");
    nextBtn->setCursor(Qt::PointingHandCursor);
    nextBtn->setStyleSheet(paginationBtnStyle);
    connect(nextBtn, &QPushButton::clicked, this, [this, sectionIndex]() {
        int pageSize = 24;
        const QList<Artist>& artists = m_sectionStates[sectionIndex].artists;
        int totalPages = (artists.size() + pageSize - 1) / pageSize;
        if (sectionIndex < m_sectionStates.size() && m_sectionStates[sectionIndex].artistsPage < totalPages - 1) {
            m_sectionStates[sectionIndex].artistsPage++;
            displayArtistsInSection(sectionIndex, artists);
        }
    });
    paginationLayout->addWidget(nextBtn);
    paginationLayout->addStretch();
    
    // Add bottom overlay to tab (will be positioned absolutely)
    bottomOverlay->setParent(artistsTab);
    bottomOverlay->raise();
    
    // Position gradient (with pagination inside) absolutely
    bottomGradientMask->setParent(bottomOverlay);
    
    paginationContainer->setVisible(false); // Hidden until we have data
    
    // Load more button (hidden)
    QPushButton* loadMoreBtn = new QPushButton("Загрузить ещё");
    loadMoreBtn->setVisible(false);
    
    m_artistsTabs.append(artistsTab);
    m_artistsScrollAreas.append(scrollArea);
    m_artistsContainers.append(container);
    m_artistsLayouts.append(gridLayout);
    m_artistsPaginationWidgets.append(paginationContainer);
    m_artistsPageLabels.append(pageLabel);
    m_loadMoreButtons.append(loadMoreBtn);
    
    // Update overlay positions when tab is resized
    auto updateOverlayPositions = [topOverlay, bottomOverlay, artistsTab, gradientMask, bottomGradientMask]() {
        if (topOverlay && bottomOverlay && artistsTab) {
            int width = artistsTab->width();
            int height = artistsTab->height();
            
            // Top gradient: 2.5 times larger (100px)
            int topGradientHeight = 100;
            topOverlay->setGeometry(0, 0, width, topGradientHeight);
            if (gradientMask) {
                gradientMask->setGeometry(0, 0, width, topGradientHeight);
            }
            
            // Bottom gradient: reduced by one third (~53px)
            int bottomGradientHeight = 53; // 80 * 2/3 ≈ 53
            bottomOverlay->setGeometry(0, height - bottomGradientHeight, width, bottomGradientHeight);
            if (bottomGradientMask) {
                bottomGradientMask->setGeometry(0, 0, width, bottomGradientHeight);
            }
        }
    };
    
    // Install event filter to catch resize events
    artistsTab->installEventFilter(new ResizeEventFilter(artistsTab, updateOverlayPositions));
    
    // Initial positioning
    QTimer::singleShot(100, [updateOverlayPositions]() { updateOverlayPositions(); });
}

void MainWindow::setupPostsTab(int sectionIndex)
{
    QWidget* postsTab = new QWidget();
    postsTab->setStyleSheet("background: transparent;");
    QVBoxLayout* postsLayout = new QVBoxLayout(postsTab);
    postsLayout->setContentsMargins(0, 0, 0, 0);
    postsLayout->setSpacing(0);
    
    // Top overlay with controls and gradient
    QWidget* topOverlay = new QWidget(postsTab);
    topOverlay->setStyleSheet("background: transparent; margin: 0; padding: 0; border: none;");
    topOverlay->setAttribute(Qt::WA_TransparentForMouseEvents, false);
    
    // Gradient mask widget - container with controls inside (height: 100px)
    QWidget* gradientMask = new QWidget(topOverlay);
    gradientMask->setStyleSheet(R"(
        QWidget {
            background: qlineargradient(x1:0, y1:0, x2:0, y2:1,
                stop:0 rgba(246,246,246,1), stop:1 rgba(246,246,246,0));
            margin: 0;
            padding: 0;
            border: none;
        }
    )");
    gradientMask->setAttribute(Qt::WA_TransparentForMouseEvents, false);
    QVBoxLayout* gradientLayout = new QVBoxLayout(gradientMask);
    gradientLayout->setContentsMargins(0, 0, 0, 0);
    gradientLayout->setSpacing(0);
    
    // Controls container - inside gradient
    QWidget* controlsContainer = new QWidget(gradientMask);
    controlsContainer->setStyleSheet("background: transparent;");
    QVBoxLayout* controlsLayout = new QVBoxLayout(controlsContainer);
    controlsLayout->setContentsMargins(16, 8, 16, 8);
    controlsLayout->setSpacing(8);
    gradientLayout->addWidget(controlsContainer);
    
    // Author name label - shows current author
    QLabel* authorNameLabel = new QLabel("Выберите автора");
    authorNameLabel->setStyleSheet(R"(
        QLabel {
            font-size: 18px;
            font-weight: 600;
            color: #1d1d1f;
            padding: 4px 0;
            background: transparent;
        }
    )");
    controlsLayout->addWidget(authorNameLabel);
    m_authorNameLabels.append(authorNameLabel);
    
    // Control panel with refresh and random author buttons
    QWidget* controlPanel = new QWidget();
    controlPanel->setStyleSheet("background: transparent;");
    QHBoxLayout* controlLayout = new QHBoxLayout(controlPanel);
    controlLayout->setContentsMargins(0, 0, 0, 0);
    controlLayout->setSpacing(10);
    
    QPushButton* refreshPostsBtn = new QPushButton("Обновить посты");
    refreshPostsBtn->setMinimumHeight(32);
    refreshPostsBtn->setCursor(Qt::PointingHandCursor);
    refreshPostsBtn->setStyleSheet(R"(
        QPushButton {
            background: rgba(0,0,0,0.05);
            color: #1d1d1f;
            padding: 6px 14px;
            border-radius: 8px;
            border: 1px solid rgba(0,0,0,0.1);
            font-weight: 500;
            font-size: 12px;
        }
        QPushButton:hover {
            background: rgba(0,0,0,0.08);
        }
    )");
    connect(refreshPostsBtn, &QPushButton::clicked, [this, sectionIndex]() {
        if (m_sectionStates[sectionIndex].hasSelectedArtist()) {
            Artist artist = m_sectionStates[sectionIndex].selectedArtist;
            m_statusLabel->setText(QString("Обновление постов: %1...").arg(artist.name()));
            m_currentArtist = artist;
            m_sectionStates[sectionIndex].artistPosts.clear();
            m_parser->getAllArtistPosts(artist);
        } else {
            m_statusLabel->setText("Сначала выберите автора");
        }
    });
    controlLayout->addWidget(refreshPostsBtn);
    
    // Random author button
    QPushButton* randomArtistBtn = new QPushButton("Случайный автор");
    randomArtistBtn->setMinimumHeight(32);
    randomArtistBtn->setCursor(Qt::PointingHandCursor);
    randomArtistBtn->setStyleSheet(R"(
        QPushButton {
            background: #5856D6;
            color: white;
            padding: 6px 14px;
            border-radius: 8px;
            border: none;
            font-weight: 500;
            font-size: 12px;
        }
        QPushButton:hover {
            background: #4240B0;
        }
    )");
    connect(randomArtistBtn, &QPushButton::clicked, [this, sectionIndex]() {
        // Copy list outside of lock to avoid holding lock during UI operation
        QList<Artist> cachedArtists;
        {
            LOCK_READ(ArtistsList);
            cachedArtists = m_allCachedArtists;
        }
        if (cachedArtists.isEmpty()) {
            m_statusLabel->setText("База авторов пуста. Нажмите 'Обновить базу'");
            return;
        }
        // Выбираем случайного автора из локальной базы
        int randomIndex = QRandomGenerator::global()->bounded(cachedArtists.size());
        Artist randomArtist = cachedArtists[randomIndex];
        m_statusLabel->setText(QString("Случайный автор: %1").arg(randomArtist.name()));
        
        // Добавляем в историю
        if (m_historyManager) {
            m_historyManager->addArtist(randomArtist);
        }
        
        // Открываем посты этого автора
        m_sectionStates[sectionIndex].selectedArtist = randomArtist;
        m_currentArtist = randomArtist;
        m_sectionStates[sectionIndex].postsPage = 0;
        // Update author name label
        if (sectionIndex < m_authorNameLabels.size() && m_authorNameLabels[sectionIndex]) {
            m_authorNameLabels[sectionIndex]->setText(randomArtist.name());
        }
        m_parser->getAllArtistPosts(randomArtist);
    });
    controlLayout->addWidget(randomArtistBtn);
    controlLayout->addStretch();
    
    controlsLayout->addWidget(controlPanel);
    
    // Add top overlay to tab
    topOverlay->setParent(postsTab);
    topOverlay->raise();
    
    // Position gradient (with controls inside) absolutely
    gradientMask->setParent(topOverlay);
    
    // Full-screen scroll area
    QScrollArea* scrollArea = new QScrollArea(postsTab);
    scrollArea->setWidgetResizable(true);
    scrollArea->setStyleSheet(R"(
        QScrollArea {
            border: none;
            background: transparent;
        }
    )");
    
    QWidget* container = new QWidget();
    container->setStyleSheet("background: transparent;");
    QGridLayout* gridLayout = new QGridLayout(container);
    gridLayout->setSpacing(16);
    gridLayout->setContentsMargins(16, 100, 16, 53); // Top padding for gradient, bottom for gradient
    
    scrollArea->setWidget(container);
    scrollArea->lower(); // Behind overlay
    postsLayout->addWidget(scrollArea, 1); // Takes remaining space
    
    // Bottom overlay with pagination and gradient
    QWidget* bottomOverlay = new QWidget(postsTab);
    bottomOverlay->setStyleSheet("background: transparent; margin: 0; padding: 0; border: none;");
    bottomOverlay->setAttribute(Qt::WA_TransparentForMouseEvents, false);
    
    // Gradient mask widget (bottom-up) - container with pagination inside (reduced by one third: ~53px)
    QWidget* bottomGradientMask = new QWidget(bottomOverlay);
    bottomGradientMask->setStyleSheet(R"(
        QWidget {
            background: qlineargradient(x1:0, y1:1, x2:0, y2:0,
                stop:0 rgba(246,246,246,1), stop:1 rgba(246,246,246,0));
            margin: 0;
            padding: 0;
            border: none;
        }
    )");
    bottomGradientMask->setAttribute(Qt::WA_TransparentForMouseEvents, false);
    QVBoxLayout* bottomGradientLayout = new QVBoxLayout(bottomGradientMask);
    bottomGradientLayout->setContentsMargins(0, 0, 0, 0);
    bottomGradientLayout->setSpacing(0);
    
    // Pagination container - inside gradient
    QWidget* paginationContainer = new QWidget(bottomGradientMask);
    paginationContainer->setStyleSheet("background: transparent;");
    QHBoxLayout* paginationLayout = new QHBoxLayout(paginationContainer);
    paginationLayout->setContentsMargins(16, 8, 16, 8);
    paginationLayout->addStretch();
    bottomGradientLayout->addWidget(paginationContainer);
    
    QString paginationBtnStyle = R"(
        QPushButton {
            background: rgba(255,255,255,0.95);
            color: #1d1d1f;
            border: 1px solid rgba(0,0,0,0.1);
            padding: 10px 24px;
            border-radius: 20px;
            font-size: 13px;
            font-weight: 500;
        }
        QPushButton:hover {
            background: #fff;
        }
        QPushButton:disabled {
            color: rgba(0,0,0,0.25);
            background: rgba(255,255,255,0.6);
        }
    )";
    
    QPushButton* prevBtn = new QPushButton("Назад");
    prevBtn->setCursor(Qt::PointingHandCursor);
    prevBtn->setStyleSheet(paginationBtnStyle);
    connect(prevBtn, &QPushButton::clicked, this, [this, sectionIndex]() {
        if (sectionIndex < m_sectionStates.size() && m_sectionStates[sectionIndex].postsPage > 0) {
            m_sectionStates[sectionIndex].postsPage--;
            displayPostsInSection(sectionIndex, m_sectionStates[sectionIndex].artistPosts);
        }
    });
    paginationLayout->addWidget(prevBtn);
    
    QLabel* pageLabel = new QLabel("1 / 1");
    pageLabel->setStyleSheet("color: rgba(0,0,0,0.6); padding: 0 20px; font-size: 13px; font-weight: 500; background: transparent;");
    paginationLayout->addWidget(pageLabel);
    
    QPushButton* nextBtn = new QPushButton("Вперед");
    nextBtn->setCursor(Qt::PointingHandCursor);
    nextBtn->setStyleSheet(paginationBtnStyle);
    connect(nextBtn, &QPushButton::clicked, this, [this, sectionIndex]() {
        int pageSize = 20;
        int totalPages = (m_sectionStates[sectionIndex].artistPosts.size() + pageSize - 1) / pageSize;
        if (sectionIndex < m_sectionStates.size() && m_sectionStates[sectionIndex].postsPage < totalPages - 1) {
            m_sectionStates[sectionIndex].postsPage++;
            displayPostsInSection(sectionIndex, m_sectionStates[sectionIndex].artistPosts);
        }
    });
    paginationLayout->addWidget(nextBtn);
    paginationLayout->addStretch();
    
    // Add bottom overlay to tab (will be positioned absolutely)
    bottomOverlay->setParent(postsTab);
    bottomOverlay->raise();
    
    // Position gradient (with pagination inside) absolutely
    bottomGradientMask->setParent(bottomOverlay);
    
    paginationContainer->setVisible(false); // Hidden until we have data
    
    m_postsTabs.append(postsTab);
    m_postsScrollAreas.append(scrollArea);
    m_postsContainers.append(container);
    m_postsLayouts.append(gridLayout);
    m_postsPaginationWidgets.append(paginationContainer);
    m_postsPageLabels.append(pageLabel);
    
    // Update overlay positions when tab is resized
    auto updateOverlayPositions = [topOverlay, bottomOverlay, postsTab, gradientMask, bottomGradientMask]() {
        if (topOverlay && bottomOverlay && postsTab) {
            int width = postsTab->width();
            int height = postsTab->height();
            
            // Top gradient: 2.5 times larger (100px)
            int topGradientHeight = 100;
            topOverlay->setGeometry(0, 0, width, topGradientHeight);
            if (gradientMask) {
                gradientMask->setGeometry(0, 0, width, topGradientHeight);
            }
            
            // Bottom gradient: reduced by one third (~53px)
            int bottomGradientHeight = 53; // 80 * 2/3 ≈ 53
            bottomOverlay->setGeometry(0, height - bottomGradientHeight, width, bottomGradientHeight);
            if (bottomGradientMask) {
                bottomGradientMask->setGeometry(0, 0, width, bottomGradientHeight);
            }
        }
    };
    
    // Install event filter to catch resize events
    postsTab->installEventFilter(new ResizeEventFilter(postsTab, updateOverlayPositions));
    
    // Initial positioning
    QTimer::singleShot(100, [updateOverlayPositions]() { updateOverlayPositions(); });
}

void MainWindow::switchToSection(int sectionIndex, int tabIndex)
{
    // UI operations are always in main thread, no locks needed
    int actualTabIndex = (tabIndex >= 0) ? tabIndex : m_sectionStates[sectionIndex].currentTab;
    
    if (m_isSwitchingSection) {
        m_pendingSectionIndex = sectionIndex;
        m_pendingTabIndex = actualTabIndex;
        return;
    }
    
    if (sectionIndex < 0 || sectionIndex >= m_sectionWidgets.size() ||
        !m_contentLayout || sectionIndex >= m_sectionStates.size() ||
        sectionIndex >= m_artistsTabs.size() || sectionIndex >= m_postsTabs.size()) {
        return;
    }
    
    // Clean up memory from other sections
    clearOtherSectionsData(sectionIndex);
    
    m_isSwitchingSection = true;
    m_currentSection = sectionIndex;
    m_currentTab = actualTabIndex;
    m_sectionStates[sectionIndex].currentTab = actualTabIndex;
    
    for (int i = 0; i < m_sectionWidgets.size(); ++i) {
        if (m_sectionWidgets[i]) {
            m_sectionWidgets[i]->setVisible(false);
        }
    }
    
    while (m_contentLayout->count() > 0) {
        QLayoutItem* item = m_contentLayout->takeAt(0);
        if (item) {
            if (item->widget()) {
                item->widget()->setParent(nullptr);
            }
            delete item;
        }
    }
    
    if (sectionIndex < m_sectionWidgets.size() && m_sectionWidgets[sectionIndex]) {
        if (m_sectionWidgets[sectionIndex]->parent() != m_contentArea) {
            m_contentLayout->insertWidget(0, m_sectionWidgets[sectionIndex]);
        }
        m_sectionWidgets[sectionIndex]->setVisible(true);
        
        // Show/hide tabs directly
        if (actualTabIndex == 0) {
            // Show artists tab, hide posts tab
            m_artistsTabs[sectionIndex]->setVisible(true);
            m_postsTabs[sectionIndex]->setVisible(false);
        } else {
            // Show posts tab, hide artists tab
            m_artistsTabs[sectionIndex]->setVisible(false);
            m_postsTabs[sectionIndex]->setVisible(true);
        }
        
        QTimer::singleShot(0, this, [this, sectionIndex, actualTabIndex]() {
            m_isSwitchingSection = false;
            onSectionTabChanged(sectionIndex, actualTabIndex);
        });
        
        updateSidebarHighlighting(sectionIndex, actualTabIndex);
    } else {
        m_isSwitchingSection = false;
    }
    
    if (m_pendingSectionIndex >= 0 && m_pendingSectionIndex != sectionIndex) {
        int pending = m_pendingSectionIndex;
        int pendingTab = m_pendingTabIndex;
        m_pendingSectionIndex = -1;
        m_pendingTabIndex = -1;
        QMetaObject::invokeMethod(this, [this, pending, pendingTab]() {
            switchToSection(pending, pendingTab);
        }, Qt::QueuedConnection);
    }
}

void MainWindow::switchToTab(int sectionIndex, int tabIndex)
{
    if (sectionIndex < 0 || sectionIndex >= m_artistsTabs.size() || 
        sectionIndex >= m_postsTabs.size()) return;
    
    // Show/hide tabs directly
    if (tabIndex == 0) {
        m_artistsTabs[sectionIndex]->setVisible(true);
        m_postsTabs[sectionIndex]->setVisible(false);
    } else {
        m_artistsTabs[sectionIndex]->setVisible(false);
        m_postsTabs[sectionIndex]->setVisible(true);
    }
    
    m_sectionStates[sectionIndex].currentTab = tabIndex;
    m_currentTab = tabIndex;
    onSectionTabChanged(sectionIndex, tabIndex);
    updateSidebarHighlighting(sectionIndex, tabIndex);
}

void MainWindow::updateSidebarHighlighting(int sectionIndex, int tabIndex)
{
    // Uncheck all buttons
    for (int i = 0; i < m_sidebarButtons.size(); ++i) {
        for (int j = 0; j < m_sidebarButtons[i].size(); ++j) {
            if (m_sidebarButtons[i][j]) {
                m_sidebarButtons[i][j]->setChecked(false);
            }
        }
    }
    
    // Check the active button
    if (sectionIndex >= 0 && sectionIndex < m_sidebarButtons.size() &&
        tabIndex >= 0 && tabIndex < m_sidebarButtons[sectionIndex].size()) {
        if (m_sidebarButtons[sectionIndex][tabIndex]) {
            m_sidebarButtons[sectionIndex][tabIndex]->setChecked(true);
        }
    }
}

void MainWindow::onSectionTabChanged(int sectionIndex, int tabIndex)
{
    if (m_isSwitchingSection) {
        m_pendingSectionIndex = sectionIndex;
        m_pendingTabIndex = tabIndex;
        return;
    }
    
    // UI operations are always in main thread, no locks needed
    if (sectionIndex < 0 || sectionIndex >= m_sectionStates.size()) {
        return;
    }
    
    // For History section, always reload content
    if (m_sectionStates[sectionIndex].currentTab == tabIndex && 
        m_currentSection == sectionIndex && sectionIndex != 1) {
        return;
    }
    
    m_sectionStates[sectionIndex].currentTab = tabIndex;
    m_currentTab = tabIndex;
    updateSidebarHighlighting(sectionIndex, tabIndex);
    
    if (sectionIndex == 0) { // Search
        if (tabIndex == 0) {
            if (m_sectionStates[sectionIndex].searchQuery.isEmpty()) {
                // Only lock when reading from potentially multi-threaded source
                QList<Artist> artists;
                {
                    LOCK_READ(ArtistsList);
                    artists = m_allCachedArtists;
                }
                if (!artists.isEmpty()) {
                    m_sectionStates[sectionIndex].artists = artists; // Save artists for pagination
                    m_sectionStates[sectionIndex].artistsPage = 0; // Reset to first page
                    displayArtistsInSection(sectionIndex, artists);
                }
            }
        } else {
            if (m_sectionStates[sectionIndex].hasSelectedArtist()) {
                if (!m_sectionStates[sectionIndex].artistPosts.isEmpty()) {
                    displayPostsInSection(sectionIndex, m_sectionStates[sectionIndex].artistPosts);
                } else {
                    Artist artist = m_sectionStates[sectionIndex].selectedArtist;
                    bool isCurrentlyLoading = (m_currentArtist.id() == artist.id() && 
                                              m_currentArtist.service() == artist.service() &&
                                              m_sectionStates[sectionIndex].artistPosts.isEmpty());
                    
                    if (!isCurrentlyLoading) {
                        m_currentArtist = artist;
                        if (m_cacheManager->hasCachedArtistPosts(artist.service(), artist.id())) {
                            QList<QJsonObject> cachedPosts = m_cacheManager->loadArtistPosts(artist.service(), artist.id());
                            QList<Post> posts;
                            for (const QJsonObject& obj : cachedPosts) {
                                posts.append(m_parser->parsePostFromJsonPublic(obj));
                            }
                            m_sectionStates[sectionIndex].artistPosts = posts;
                            displayPostsInSection(sectionIndex, posts);
                        } else {
                            m_parser->getAllArtistPosts(artist);
                        }
                    }
                }
            }
        }
    } else if (sectionIndex == 1) { // History
        if (tabIndex == 0) {
            QList<Artist> artists = m_historyManager ? m_historyManager->getRecentArtists(0) : QList<Artist>(); // 0 = no limit
            m_sectionStates[sectionIndex].artists = artists; // Save artists for pagination
            m_sectionStates[sectionIndex].artistsPage = 0; // Reset to first page
            displayArtistsInSection(sectionIndex, artists);
        } else {
            QList<Post> posts = m_historyManager ? m_historyManager->getRecentPosts(0) : QList<Post>(); // 0 = no limit
            m_sectionStates[sectionIndex].artistPosts = posts; // Save posts for pagination
            m_sectionStates[sectionIndex].postsPage = 0; // Reset to first page
            displayPostsInSection(sectionIndex, posts);
        }
    }
    // sectionIndex == 2 (Offline) - not implemented
}

void MainWindow::onArtistSelected(int sectionIndex, const Artist& artist)
{
    if (m_historyManager) {
        m_historyManager->addArtist(artist);
    }
    
    // Clean up memory before loading new artist data
    clearThumbnailQueue();
    QPixmapCache::clear();
    
    SectionState& state = m_sectionStates[sectionIndex];
    state.selectedArtist = artist;
    m_currentArtist = artist;
    state.artistPosts.clear();
    state.artistPosts.squeeze(); // Release memory
    
    // Update author name label
    if (sectionIndex < m_authorNameLabels.size() && m_authorNameLabels[sectionIndex]) {
        m_authorNameLabels[sectionIndex]->setText(artist.name());
    }
    
    switchToTab(sectionIndex, 1);
    m_statusLabel->setText(QString("Загрузка постов: %1").arg(artist.name()));
    
    if (m_cacheManager->hasCachedArtistPosts(artist.service(), artist.id())) {
        QList<QJsonObject> cachedPosts = m_cacheManager->loadArtistPosts(artist.service(), artist.id());
        QList<Post> posts;
        for (const QJsonObject& obj : cachedPosts) {
            posts.append(m_parser->parsePostFromJsonPublic(obj));
        }
        state.artistPosts = posts;
        displayPostsInSection(sectionIndex, posts);
    } else {
        m_parser->getAllArtistPosts(artist);
    }
}

void MainWindow::onPostSelected(int sectionIndex, const Post& post)
{
    Q_UNUSED(sectionIndex);
    
    if (m_historyManager) {
        m_historyManager->addPost(post);
    }
    
    bool hasFullData = !post.attachments().isEmpty() || !post.files().isEmpty() || !post.embeds().isEmpty();
    
    if (!hasFullData) {
        m_pendingPostToOpen = post;
        m_hasPendingPost = true;
        m_parser->getPost(post.service(), post.author(), post.id());
    } else {
        PostViewer* viewer = new PostViewer(post, m_cacheManager, this);
        connect(viewer, &PostViewer::openAuthorRequested, this, &MainWindow::onOpenAuthorFromViewer);
        viewer->show();
    }
}

void MainWindow::displayArtistsInSection(int sectionIndex, const QList<Artist>& artists)
{
    if (sectionIndex < 0 || sectionIndex >= m_artistsLayouts.size()) {
        return;
    }
    
    QGridLayout* layout = m_artistsLayouts[sectionIndex];
    if (!layout) return;
    
    // Собираем все виджеты перед удалением, чтобы очистить m_previewDownloads
    QSet<QLabel*> labelsToRemove;
    while (layout->count() > 0) {
        QLayoutItem* item = layout->takeAt(0);
        if (item) {
            if (item->widget()) {
                // Находим все QLabel внутри виджета
                QList<QLabel*> labels = item->widget()->findChildren<QLabel*>();
                labelsToRemove.unite(QSet<QLabel*>(labels.begin(), labels.end()));
                item->widget()->deleteLater();
            }
            delete item;
        }
    }
    
    // Очищаем m_previewDownloads для удаленных виджетов
    QMutableMapIterator<QString, PreviewDownloadInfo> it(m_previewDownloads);
    while (it.hasNext()) {
        it.next();
        if (labelsToRemove.contains(it.value().label)) {
            // Отписываемся от загрузки
            MediaDownloadManager* manager = MediaDownloadManager::instance();
            manager->unsubscribeFromDownload(it.key(), this);
            it.remove();
        }
    }
    
    // Pagination
    int pageSize = 24;
    int currentPage = (sectionIndex < m_sectionStates.size()) ? m_sectionStates[sectionIndex].artistsPage : 0;
    int startIndex = currentPage * pageSize;
    int endIndex = qMin(startIndex + pageSize, artists.size());
    
    QList<Artist> pageArtists = artists.mid(startIndex, endIndex - startIndex);
    
    int row = 0, col = 0;
    const int maxCols = 4;
    
    for (const Artist& artist : pageArtists) {
        displayArtistButton(artist, layout, row, col, sectionIndex);
        col++;
        if (col >= maxCols) {
            col = 0;
            row++;
        }
    }
    
    // Update fixed pagination widget
    int totalPages = (artists.size() + pageSize - 1) / pageSize;
    if (sectionIndex < m_artistsPaginationWidgets.size() && m_artistsPaginationWidgets[sectionIndex]) {
        bool showPagination = totalPages > 1;
        m_artistsPaginationWidgets[sectionIndex]->setVisible(showPagination);
        
        if (showPagination && sectionIndex < m_artistsPageLabels.size() && m_artistsPageLabels[sectionIndex]) {
            m_artistsPageLabels[sectionIndex]->setText(QString("%1 / %2").arg(currentPage + 1).arg(totalPages));
            
            // Update button states
            QWidget* paginationContainer = m_artistsPaginationWidgets[sectionIndex];
            QList<QPushButton*> buttons = paginationContainer->findChildren<QPushButton*>();
            for (QPushButton* btn : buttons) {
                if (btn->text() == "Назад") {
                    btn->setEnabled(currentPage > 0);
                } else if (btn->text() == "Вперед") {
                    btn->setEnabled(currentPage < totalPages - 1);
                }
            }
        }
    }
}

void MainWindow::displayPostsInSection(int sectionIndex, const QList<Post>& posts)
{
    if (m_isDisplayingPosts) return;
    if (sectionIndex < 0 || sectionIndex >= m_postsLayouts.size()) return;
    
    QGridLayout* layout = m_postsLayouts[sectionIndex];
    if (!layout) return;
    
    m_isDisplayingPosts = true;
    
    // Clear thumbnail download queue before removing widgets
    clearThumbnailQueue();
    
    while (layout->count() > 0) {
        QLayoutItem* item = layout->takeAt(0);
        if (item) {
            if (item->widget()) {
                item->widget()->deleteLater();
            }
            delete item;
        }
    }
    
    int pageSize = 20;
    int currentPage = (sectionIndex < m_sectionStates.size()) ? m_sectionStates[sectionIndex].postsPage : 0;
    int startIndex = currentPage * pageSize;
    int endIndex = qMin(startIndex + pageSize, posts.size());
    
    QList<Post> pagePosts = posts.mid(startIndex, endIndex - startIndex);
    
    int row = 0, col = 0;
    const int maxCols = 3;
    const int cardWidth = 350;
    const int thumbHeight = 250;
    const int minTitleHeight = 50;
    
    for (const Post& post : pagePosts) {
        // Calculate title height based on text length
        QFontMetrics fm(QFont("", 13, QFont::Bold));
        int textWidth = cardWidth - 24;
        QRect boundingRect = fm.boundingRect(QRect(0, 0, textWidth, 1000), Qt::TextWordWrap, post.title());
        int titleHeight = qMax(minTitleHeight, boundingRect.height() + 16);
        int cardHeight = thumbHeight + titleHeight;
        
        QWidget* cardWidget = new QWidget();
        cardWidget->setObjectName("postCard");
        cardWidget->setFixedSize(cardWidth, cardHeight);
        cardWidget->setCursor(Qt::PointingHandCursor);
        cardWidget->setStyleSheet(R"(
            #postCard {
                background: rgba(255,255,255,0.8);
                border: 1px solid rgba(0,0,0,0.08);
                border-radius: 12px;
            }
            #postCard:hover {
                background: #fff;
                border-color: rgba(0,122,255,0.3);
            }
        )");
        
        QVBoxLayout* cardLayout = new QVBoxLayout(cardWidget);
        cardLayout->setContentsMargins(0, 0, 0, 0);
        cardLayout->setSpacing(0);
        
        // Thumbnail - full width
        QLabel* thumbnailLabel = new QLabel(cardWidget);
        thumbnailLabel->setFixedSize(cardWidth, thumbHeight);
        thumbnailLabel->setAlignment(Qt::AlignCenter);
        thumbnailLabel->setScaledContents(false);
        thumbnailLabel->setStyleSheet(R"(
            QLabel {
                background: #f5f5f7;
                border-top-left-radius: 12px;
                border-top-right-radius: 12px;
                color: rgba(0,0,0,0.35);
                font-size: 12px;
            }
        )");
        thumbnailLabel->setText("Загрузка...");
        cardLayout->addWidget(thumbnailLabel);
        
        // Progress bar - positioned at bottom of thumbnail area
        QProgressBar* progressBar = new QProgressBar(cardWidget);
        progressBar->setMinimum(0);
        progressBar->setMaximum(100);
        progressBar->setValue(0);
        progressBar->setGeometry(10, thumbHeight - 12, cardWidth - 20, 4);
        progressBar->setTextVisible(false);
        progressBar->setStyleSheet(R"(
            QProgressBar {
                border: none;
                background: rgba(0,0,0,0.15);
                border-radius: 2px;
            }
            QProgressBar::chunk {
                background: #007AFF;
                border-radius: 2px;
            }
        )");
        progressBar->hide();
        progressBar->raise();
        
        QString thumbnailUrl = post.thumbnail();
        if (!thumbnailUrl.isEmpty()) {
            queueThumbnailDownload(thumbnailLabel, progressBar, thumbnailUrl, cardWidth, thumbHeight);
        } else {
            QString filePath = findImagePath(post);
            if (!filePath.isEmpty()) {
                if (!filePath.startsWith("http")) {
                    filePath = filePath.startsWith("/") 
                        ? QString("https://kemono.cr%1").arg(filePath)
                        : QString("https://kemono.cr/%1").arg(filePath);
                }
                queueThumbnailDownload(thumbnailLabel, progressBar, filePath, cardWidth, thumbHeight);
            } else {
                thumbnailLabel->setText("Нет превью");
            }
        }
        
        // Title container - dynamic height based on text
        QWidget* titleContainer = new QWidget(cardWidget);
        titleContainer->setFixedHeight(titleHeight);
        titleContainer->setStyleSheet(R"(
            QWidget {
                background: transparent;
                border-bottom-left-radius: 12px;
                border-bottom-right-radius: 12px;
            }
        )");
        
        QVBoxLayout* titleLayout = new QVBoxLayout(titleContainer);
        titleLayout->setContentsMargins(12, 8, 12, 8);
        titleLayout->setSpacing(0);
        
        QLabel* titleLabel = new QLabel(post.title(), titleContainer);
        titleLabel->setWordWrap(true);
        titleLabel->setAlignment(Qt::AlignTop | Qt::AlignLeft);
        titleLabel->setStyleSheet(R"(
            QLabel {
                font-weight: 500;
                font-size: 13px;
                color: #1d1d1f;
                background: transparent;
            }
        )");
        titleLayout->addWidget(titleLabel);
        
        cardLayout->addWidget(titleContainer);
        
        // Click handler
        Post capturedPost = post;
        cardWidget->installEventFilter(this);
        cardWidget->setProperty("postData", QVariant::fromValue(capturedPost));
        cardWidget->setProperty("sectionIndex", sectionIndex);
        
        layout->addWidget(cardWidget, row, col);
        col++;
        if (col >= maxCols) {
            col = 0;
            row++;
        }
    }
    
    // Update fixed pagination widget
    int totalPages = (posts.size() + pageSize - 1) / pageSize;
    if (sectionIndex < m_postsPaginationWidgets.size() && m_postsPaginationWidgets[sectionIndex]) {
        bool showPagination = totalPages > 1;
        m_postsPaginationWidgets[sectionIndex]->setVisible(showPagination);
        
        if (showPagination && sectionIndex < m_postsPageLabels.size() && m_postsPageLabels[sectionIndex]) {
            m_postsPageLabels[sectionIndex]->setText(QString("%1 / %2").arg(currentPage + 1).arg(totalPages));
            
            // Update button states
            QWidget* paginationContainer = m_postsPaginationWidgets[sectionIndex];
            QList<QPushButton*> buttons = paginationContainer->findChildren<QPushButton*>();
            for (QPushButton* btn : buttons) {
                if (btn->text() == "Назад") {
                    btn->setEnabled(currentPage > 0);
                } else if (btn->text() == "Вперед") {
                    btn->setEnabled(currentPage < totalPages - 1);
                }
            }
        }
    }
    
    m_isDisplayingPosts = false;
}

void MainWindow::clearSectionContent(int sectionIndex, int tabIndex)
{
    if (tabIndex == 0) { // Artists
        if (sectionIndex < m_artistsLayouts.size()) {
            QLayoutItem* item;
            while ((item = m_artistsLayouts[sectionIndex]->takeAt(0)) != nullptr) {
                delete item->widget();
                delete item;
            }
        }
    } else { // Posts
        if (sectionIndex < m_postsLayouts.size()) {
            QLayoutItem* item;
            while ((item = m_postsLayouts[sectionIndex]->takeAt(0)) != nullptr) {
                delete item->widget();
                delete item;
            }
        }
    }
}

