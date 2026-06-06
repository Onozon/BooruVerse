#include "gui/postviewer.h"
#include "gui/mediaviewer.h"
#include "core/mediadownloadmanager.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QFileInfo>
#include <QDebug>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>
#include <QPixmap>
#include <QRegularExpression>
#include <QMouseEvent>
#include <QEvent>
#include <QCloseEvent>
#include <QDir>
#include <QFile>
#include <QDesktopServices>
#include <QPointer>
#include <QGraphicsDropShadowEffect>
#include <QPainter>
#include <QPainterPath>

namespace {
    // Round all corners of pixmap for card preview
    QPixmap roundAllCorners(const QPixmap& src, int radius) {
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
}

PostViewer::PostViewer(const Post& post, CacheManager* cacheManager, QWidget *parent)
    : QMainWindow(parent)
    , m_post(post)
    , m_cacheManager(cacheManager)
    , m_networkManager(new QNetworkAccessManager(this))
    , m_isClosing(false)
{
    setWindowTitle(QString("Пост: %1").arg(post.title()));
    setGeometry(100, 100, 1200, 800);
    setMinimumSize(600, 400);
    
    setupUI();
    loadPostMedia();
}

PostViewer::~PostViewer()
{
    cancelAllDownloads();
    
    // Отписываемся от всех загрузок
    MediaDownloadManager* manager = MediaDownloadManager::instance();
    for (auto it = m_progressBars.begin(); it != m_progressBars.end(); ++it) {
        manager->unsubscribeFromDownload(it.key(), this);
    }
    
    m_progressBars.clear();
    m_previewLabels.clear();
    m_downloadingFiles.clear();
}

void PostViewer::closeEvent(QCloseEvent* event)
{
    m_isClosing = true;
    cancelAllDownloads();
    event->accept();
}

void PostViewer::cancelAllDownloads()
{
    // Очищаем очередь
    m_downloadQueue.clear();
    
    // Отменяем все активные загрузки через MediaDownloadManager
    MediaDownloadManager* manager = MediaDownloadManager::instance();
    for (auto it = m_downloadingFiles.begin(); it != m_downloadingFiles.end(); ++it) {
        manager->cancelDownload(it.key());
    }
    
    // Отменяем старые загрузки (если есть)
    for (QNetworkReply* reply : m_activeReplies) {
        if (reply) {
            reply->abort();
            reply->deleteLater();
        }
    }
    m_activeReplies.clear();
}

void PostViewer::setupUI()
{
    // Light macOS theme
    setStyleSheet(R"(
        QMainWindow {
            background: rgba(246, 246, 246, 0.98);
        }
        QScrollBar:vertical {
            background: transparent;
            width: 8px;
            border-radius: 4px;
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
    )");
    
    QWidget* centralWidget = new QWidget(this);
    centralWidget->setStyleSheet("background: transparent;");
    setCentralWidget(centralWidget);
    
    QVBoxLayout* mainLayout = new QVBoxLayout(centralWidget);
    mainLayout->setContentsMargins(20, 20, 20, 20);
    mainLayout->setSpacing(16);
    
    // Header with title and buttons
    QWidget* headerWidget = new QWidget(this);
    headerWidget->setStyleSheet("background: transparent;");
    QHBoxLayout* headerLayout = new QHBoxLayout(headerWidget);
    headerLayout->setContentsMargins(0, 0, 0, 0);
    headerLayout->setSpacing(12);
    
    QLabel* titleLabel = new QLabel(m_post.title(), this);
    titleLabel->setWordWrap(true);
    titleLabel->setStyleSheet(R"(
        QLabel {
            font-size: 18px;
            font-weight: 600;
            color: #1d1d1f;
            padding: 8px 0;
            background: transparent;
        }
    )");
    headerLayout->addWidget(titleLabel, 1);
    
    QString btnStyle = R"(
        QPushButton {
            background: rgba(0,0,0,0.05);
            color: #1d1d1f;
            border: 1px solid rgba(0,0,0,0.1);
            padding: 8px 14px;
            border-radius: 8px;
            font-weight: 500;
            font-size: 12px;
        }
        QPushButton:hover {
            background: rgba(0,0,0,0.08);
        }
    )";
    
    // Author button
    QPushButton* authorBtn = new QPushButton("К автору", this);
    authorBtn->setCursor(Qt::PointingHandCursor);
    authorBtn->setStyleSheet(btnStyle);
    connect(authorBtn, &QPushButton::clicked, this, [this]() {
        emit openAuthorRequested(m_post.service(), m_post.author(), m_post.author());
    });
    headerLayout->addWidget(authorBtn);
    
    QPushButton* openFolderBtn = new QPushButton("Открыть папку", this);
    openFolderBtn->setCursor(Qt::PointingHandCursor);
    openFolderBtn->setStyleSheet(btnStyle);
    connect(openFolderBtn, &QPushButton::clicked, this, &PostViewer::onOpenFolderClicked);
    headerLayout->addWidget(openFolderBtn);
    
    mainLayout->addWidget(headerWidget);
    
    // Scroll area for media
    m_scrollArea = new QScrollArea(this);
    m_scrollArea->setWidgetResizable(true);
    m_scrollArea->setStyleSheet("QScrollArea { border: none; background: transparent; }");
    
    m_container = new QWidget();
    m_container->setStyleSheet("background: transparent;");
    m_mediaLayout = new QGridLayout(m_container);
    m_mediaLayout->setSpacing(20);
    m_mediaLayout->setContentsMargins(15, 15, 15, 15);
    
    m_scrollArea->setWidget(m_container);
    mainLayout->addWidget(m_scrollArea);
}

bool PostViewer::isImageFormat(const QString& filename) const
{
    QString ext = QFileInfo(filename).suffix().toLower();
    return ext == "jpg" || ext == "jpeg" || ext == "png" || 
           ext == "gif" || ext == "webp" || ext == "bmp" || ext == "tiff";
}

void PostViewer::loadPostMedia()
{
    int row = 0;
    int col = 0;
    const int maxCols = 3;
    const int cardWidth = 350;
    const int cardHeight = 300;
    
    auto addMediaItem = [this, &row, &col, maxCols, cardWidth, cardHeight](const QVariantMap& item, const QString& sourceType) {
        QVariantMap mediaItem;
        QString path;
        QString name;
        
        if (sourceType == "file") {
            path = item.value("path").toString();
            name = item.value("name").toString();
        } else if (sourceType == "attachment") {
            if (item.contains("path")) {
                path = item.value("path").toString();
            } else if (item.contains("url")) {
                path = item.value("url").toString();
            }
            name = item.value("name").toString();
        } else if (sourceType == "embed") {
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
            return;
        }
        
        QString fullUrl;
        if (path.startsWith("http://") || path.startsWith("https://")) {
            fullUrl = path;
        } else if (path.startsWith("/")) {
            fullUrl = QString("https://kemono.cr%1").arg(path);
        } else {
            fullUrl = QString("https://kemono.cr/%1").arg(path);
        }
        
        QString filename = name.isEmpty() ? QFileInfo(path).fileName() : name;
        QString fileExt = QFileInfo(filename).suffix().toLower();
        bool isImage = isImageFormat(filename);
        
        mediaItem["url"] = fullUrl;
        mediaItem["filename"] = filename;
        mediaItem["post_id"] = m_post.id();
        mediaItem["post_title"] = m_post.title();
        mediaItem["author_name"] = QString("%1_%2_%3")
            .arg(m_post.service())
            .arg(m_post.author())
            .arg(m_post.id());
        
        m_mediaItems.append(mediaItem);
        
        // Create media card - clean macOS style
        QWidget* cardWidget = new QWidget(m_container);
        cardWidget->setFixedSize(cardWidth, cardHeight);
        cardWidget->setObjectName("mediaCard");
        cardWidget->setCursor(Qt::PointingHandCursor);
        cardWidget->setStyleSheet(R"(
            #mediaCard {
                background: rgba(255,255,255,0.8);
                border: 1px solid rgba(0,0,0,0.08);
                border-radius: 12px;
            }
            #mediaCard:hover {
                background: #fff;
                border-color: rgba(0,122,255,0.3);
            }
        )");
        
        // Preview label - full card size, no layout needed
        QLabel* previewLabel = new QLabel(cardWidget);
        previewLabel->setGeometry(0, 0, cardWidth, cardHeight);
        previewLabel->setAlignment(Qt::AlignCenter);
        previewLabel->setScaledContents(false);
        previewLabel->setStyleSheet(R"(
            QLabel {
                background: #f5f5f7;
                border-radius: 12px;
                color: rgba(0,0,0,0.35);
                font-size: 12px;
            }
        )");
        
        // Format badge in corner - macOS style
        QLabel* formatBadge = new QLabel(fileExt.toUpper(), cardWidget);
        formatBadge->setStyleSheet(R"(
            QLabel {
                background: rgba(0,0,0,0.6);
                color: white;
                font-size: 9px;
                font-weight: 600;
                padding: 3px 8px;
                border-radius: 4px;
            }
        )");
        formatBadge->adjustSize();
        formatBadge->move(cardWidth - formatBadge->width() - 10, 10);
        formatBadge->raise();
        
        // Progress bar - positioned at bottom, inside the card
        QProgressBar* progressBar = new QProgressBar(cardWidget);
        progressBar->setMinimum(0);
        progressBar->setMaximum(100);
        progressBar->setValue(0);
        progressBar->setGeometry(10, cardHeight - 14, cardWidth - 20, 4);
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
        
        // Check if file already exists
        QString filepath = getMediaFilepath(filename);
        QFileInfo fileInfo(filepath);
        bool fileExists = fileInfo.exists() && fileInfo.size() > 0;
        
        // Save references
        m_progressBars[fullUrl] = progressBar;
        m_previewLabels[fullUrl] = previewLabel;
        
        if (isImage) {
            if (fileExists) {
                QPixmap pixmap(filepath);
                if (!pixmap.isNull()) {
                    QPixmap scaled = pixmap.scaled(cardWidth, cardHeight, Qt::KeepAspectRatio, Qt::FastTransformation);
                    previewLabel->setPixmap(roundAllCorners(scaled, 16));
                } else {
                    previewLabel->setText("⏳ Загрузка...");
                }
            } else {
                previewLabel->setText("⏳ В очереди...");
                queueDownload(fullUrl, filepath, progressBar, previewLabel, true);
            }
        } else {
            previewLabel->setText(filename);
            previewLabel->setWordWrap(true);
            
            if (fileExists) {
                // progressBar already hidden by default
            } else {
                QPushButton* downloadBtn = new QPushButton("Скачать", previewLabel);
                downloadBtn->setGeometry((cardWidth - 100) / 2, cardHeight - 50, 100, 34);
                downloadBtn->setCursor(Qt::PointingHandCursor);
                downloadBtn->setStyleSheet(R"(
                    QPushButton {
                        background: #007AFF;
                        color: white;
                        border: none;
                        border-radius: 8px;
                        font-size: 12px;
                        font-weight: 500;
                    }
                    QPushButton:hover {
                        background: #0056CC;
                    }
                )");
                
                connect(downloadBtn, &QPushButton::clicked, [this, fullUrl, filepath, progressBar, previewLabel, downloadBtn]() {
                    downloadBtn->setEnabled(false);
                    downloadBtn->setText("...");
                    queueDownload(fullUrl, filepath, progressBar, previewLabel, false);
                });
            }
        }
        
        // Connect click for viewer
        QVariantMap clickData = mediaItem;
        cardWidget->installEventFilter(this);
        cardWidget->setProperty("mediaItem", QVariant::fromValue(clickData));
        
        m_mediaLayout->addWidget(cardWidget, row, col);
        
        col++;
        if (col >= maxCols) {
            col = 0;
            row++;
        }
    };
    
    QList<QVariantMap> attachments = m_post.attachments();
    QList<QVariantMap> files = m_post.files();
    QList<QVariantMap> embeds = m_post.embeds();
    
    for (const QVariantMap& attachment : attachments) {
        addMediaItem(attachment, "attachment");
    }
    for (const QVariantMap& file : files) {
        addMediaItem(file, "file");
    }
    for (const QVariantMap& embed : embeds) {
        if (embed.contains("url") || embed.contains("path")) {
            addMediaItem(embed, "embed");
        }
    }
    
    if (m_mediaItems.isEmpty()) {
        QLabel* noMediaLabel = new QLabel("Нет медиафайлов в этом посте", m_container);
        noMediaLabel->setAlignment(Qt::AlignCenter);
        noMediaLabel->setStyleSheet("font-size: 14px; color: #666; padding: 20px;");
        m_mediaLayout->addWidget(noMediaLabel, 0, 0, 1, 4);
    }
}

bool PostViewer::eventFilter(QObject* obj, QEvent* event)
{
    if (event->type() == QEvent::MouseButtonRelease) {
        QWidget* widget = qobject_cast<QWidget*>(obj);
        if (widget && widget->property("mediaItem").isValid()) {
            QVariantMap mediaItem = widget->property("mediaItem").toMap();
            onMediaClicked(mediaItem);
            return true;
        }
    }
    return QMainWindow::eventFilter(obj, event);
}

QString PostViewer::getMediaFilepath(const QString& filename) const
{
    QString authorName = QString("%1_%2_%3")
        .arg(m_post.service())
        .arg(m_post.author())
        .arg(m_post.id());
    
    QString safeTitle = m_post.title();
    QRegularExpression regex("[<>:\"/\\|?*]");
    safeTitle.replace(regex, "_");
    safeTitle = safeTitle.left(50);
    
    QString postDir = QString("downloads/%1/%2").arg(authorName, safeTitle);
    return QString("%1/%2").arg(postDir, filename);
}

void PostViewer::queueDownload(const QString& url, const QString& filepath, 
                               QProgressBar* progressBar, QLabel* previewLabel, bool isImage)
{
    // Проверяем, уже скачан ли файл
    if (QFile::exists(filepath)) {
        if (isImage && previewLabel) {
            QPixmap pixmap(filepath);
            if (!pixmap.isNull()) {
                QPixmap scaled = pixmap.scaled(350, 300, Qt::KeepAspectRatio, Qt::FastTransformation);
                previewLabel->setPixmap(roundAllCorners(scaled, 12));
                previewLabel->setText("");
            }
        }
        if (progressBar) {
            progressBar->hide();
        }
        return;
    }
    
    // Проверяем, не в процессе ли уже загрузка
    if (m_downloadingFiles.contains(url)) {
        return;
    }
    
    // Добавляем в очередь
    DownloadQueueItem item;
    item.url = url;
    item.filepath = filepath;
    item.progressBar = progressBar;
    item.previewLabel = previewLabel;
    item.isImage = isImage;
    
    m_downloadQueue.enqueue(item);
    
    // Запускаем обработку очереди
    processDownloadQueue();
}

void PostViewer::processDownloadQueue()
{
    // Запускаем все загрузки сразу без лимита
    while (!m_downloadQueue.isEmpty() && !m_isClosing) {
        DownloadQueueItem item = m_downloadQueue.dequeue();
        downloadMediaFile(item.url, item.filepath, item.progressBar, item.previewLabel, item.isImage);
    }
}

void PostViewer::onDownloadFinished(const QString& url)
{
    m_downloadingFiles.remove(url);
    // Больше не нужно отслеживать количество активных загрузок
    // MediaDownloadManager сам управляет загрузками
}

void PostViewer::downloadMediaFile(const QString& url, const QString& filepath, 
                                    QProgressBar* progressBar, QLabel* previewLabel, bool isImage)
{
    if (m_isClosing) return;
    
    // Проверяем, существует ли файл
    QFileInfo fileInfo(filepath);
    if (fileInfo.exists() && fileInfo.size() > 0) {
        // Файл уже существует
        if (progressBar) {
            progressBar->hide();
        }
        if (isImage && previewLabel) {
            QPixmap pixmap(filepath);
            if (!pixmap.isNull()) {
                QPixmap scaled = pixmap.scaled(350, 300, Qt::KeepAspectRatio, Qt::FastTransformation);
                previewLabel->setPixmap(roundAllCorners(scaled, 12));
                previewLabel->setText("");
            }
        }
        return;
    }
    
    // Сохраняем ссылки на UI элементы для этого URL
    if (progressBar) {
        m_progressBars[url] = progressBar;
    }
    if (previewLabel) {
        m_previewLabels[url] = previewLabel;
    }
    
    // Сохраняем информацию о типе медиа
    m_downloadingFiles[url] = filepath;
    
    // Используем MediaDownloadManager для синхронизации загрузок
    MediaDownloadManager* manager = MediaDownloadManager::instance();
    manager->startDownload(url, filepath, this);
}

void PostViewer::onDownloadProgress(const QString& url, qint64 bytesReceived, qint64 bytesTotal)
{
    if (m_isClosing) return;
    
    QProgressBar* progressBar = m_progressBars.value(url);
    if (progressBar && bytesTotal > 0) {
        progressBar->show();
        int percent = static_cast<int>((bytesReceived * 100) / bytesTotal);
        progressBar->setValue(percent);
    }
}

void PostViewer::onDownloadFinished(const QString& url, const QString& filepath, bool success)
{
    if (m_isClosing) return;
    
    QProgressBar* progressBar = m_progressBars.value(url);
    QLabel* previewLabel = m_previewLabels.value(url);
    
    if (success) {
        // Скрываем прогресс-бар
        if (progressBar) {
            progressBar->hide();
        }
        
        // Загружаем изображение в preview, если это изображение
        if (previewLabel) {
            QFileInfo fileInfo(filepath);
            if (fileInfo.exists() && isImageFormat(filepath)) {
                QPixmap pixmap(filepath);
                if (!pixmap.isNull()) {
                    QPixmap scaled = pixmap.scaled(350, 300, Qt::KeepAspectRatio, Qt::FastTransformation);
                    previewLabel->setPixmap(roundAllCorners(scaled, 12));
                    previewLabel->setText("");
                }
            }
        }
        
        onDownloadFinished(url);
    } else {
        // Показываем ошибку и кнопку повтора
        if (progressBar) {
            progressBar->hide();
        }
        if (previewLabel) {
            previewLabel->setText("");
            
            // Добавляем кнопку повтора
            QPushButton* retryBtn = new QPushButton("Повторить", previewLabel);
            retryBtn->setGeometry((240 - 100) / 2, (196 - 35) / 2, 100, 35);
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
            
            QString filepathCopy = filepath;
            bool isImageCopy = isImageFormat(filepath);
            QObject::connect(retryBtn, &QPushButton::clicked, [this, url, filepathCopy, progressBar, previewLabel, isImageCopy, retryBtn]() {
                if (!m_isClosing && previewLabel) {
                    retryBtn->deleteLater();
                    previewLabel->setText("Загрузка...");
                    if (progressBar) {
                        progressBar->setValue(0);
                        progressBar->show();
                    }
                    queueDownload(url, filepathCopy, progressBar, previewLabel, isImageCopy);
                }
            });
        }
    }
}

void PostViewer::loadMediaPreview(QLabel* label, QWidget* mediaWidget, const QString& mediaUrl, const QString& filename)
{
    Q_UNUSED(label)
    Q_UNUSED(mediaWidget)
    Q_UNUSED(mediaUrl)
    Q_UNUSED(filename)
}

void PostViewer::showRetryButton(QLabel* label, QWidget* mediaWidget, const QString& mediaUrl, const QString& filename)
{
    Q_UNUSED(label)
    Q_UNUSED(mediaWidget)
    Q_UNUSED(mediaUrl)
    Q_UNUSED(filename)
}

void PostViewer::onRetryClicked()
{
}

void PostViewer::onMediaClicked(const QVariantMap& mediaItem)
{
    int clickedIndex = -1;
    for (int i = 0; i < m_mediaItems.size(); ++i) {
        if (m_mediaItems[i]["url"].toString() == mediaItem["url"].toString() &&
            m_mediaItems[i]["filename"].toString() == mediaItem["filename"].toString()) {
            clickedIndex = i;
            break;
        }
    }
    
    if (clickedIndex >= 0) {
        MediaViewer* viewer = new MediaViewer(m_mediaItems, clickedIndex, m_cacheManager, this);
        viewer->show();
    } else {
        QList<QVariantMap> singleItem;
        singleItem.append(mediaItem);
        MediaViewer* viewer = new MediaViewer(singleItem, 0, m_cacheManager, this);
        viewer->show();
    }
}

void PostViewer::onOpenFolderClicked()
{
    QString authorName = QString("%1_%2_%3")
        .arg(m_post.service())
        .arg(m_post.author())
        .arg(m_post.id());
    
    QString safeTitle = m_post.title();
    QRegularExpression regex("[<>:\"/\\|?*]");
    safeTitle.replace(regex, "_");
    safeTitle = safeTitle.left(50);
    
    QString postDir = QString("downloads/%1/%2").arg(authorName, safeTitle);
    QDir dir(postDir);
    
    if (!dir.exists()) {
        dir.mkpath(".");
    }
    
    QDesktopServices::openUrl(QUrl::fromLocalFile(dir.absolutePath()));
}
