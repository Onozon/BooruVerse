#include "gui/mediaviewer.h"
#include "gui/mainwindow.h"
#include "cache/cachemanager.h"
#include "core/mediadownloadmanager.h"
#include "models/artist.h"
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QFileInfo>
#include <QDir>
#include <QDebug>
#include <QResizeEvent>
#include <QFile>
#include <QRegularExpression>
#include <QNetworkRequest>
#include <QUrl>
#include <QDesktopServices>
#include <QBuffer>
#include <QPixmap>

MediaViewer::MediaViewer(const QList<QVariantMap>& mediaItems, int currentIndex, CacheManager* cacheManager, QWidget *parent)
    : QMainWindow(parent)
    , m_mediaItems(mediaItems)
    , m_currentIndex(currentIndex)
    , m_isFullImageLoaded(false)
    , m_previewReply(nullptr)
    , m_fileDownloadReply(nullptr)
    , m_cacheManager(cacheManager)
    , m_downloadWidget(nullptr)
    , m_downloadButton(nullptr)
    , m_showButton(nullptr)
    , m_progressBar(nullptr)
    , m_fileInfoLabel(nullptr)
    , m_movie(nullptr)
    , m_isDownloading(false)
    , m_loadingWidget(nullptr)
    , m_imageProgressBar(nullptr)
    , m_loadingLabel(nullptr)
{
    setGeometry(100, 100, 800, 600);
    setMinimumSize(400, 300);
    
    m_networkManager = new QNetworkAccessManager(this);
    
    setupUI();
    loadCurrentMedia();
    
    setFocus();
    setFocusPolicy(Qt::StrongFocus);
}

MediaViewer::~MediaViewer()
{
    // Отписываемся от всех загрузок
    if (!m_currentDownloadUrl.isEmpty()) {
        MediaDownloadManager* manager = MediaDownloadManager::instance();
        manager->unsubscribeFromDownload(m_currentDownloadUrl, this);
    }
    
    if (m_movie) {
        m_movie->stop();
        delete m_movie;
        m_movie = nullptr;
    }
}

void MediaViewer::setupUI()
{
    setStatusBar(nullptr);
    
    // Dark theme for media viewer (better for viewing images)
    setStyleSheet(R"(
        QMainWindow {
            background: #1a1a1a;
        }
        QScrollBar:vertical {
            background: transparent;
            width: 8px;
            border-radius: 4px;
        }
        QScrollBar::handle:vertical {
            background: rgba(255,255,255,0.2);
            border-radius: 4px;
            min-height: 40px;
        }
        QScrollBar::handle:vertical:hover {
            background: rgba(255,255,255,0.3);
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
            background: rgba(255,255,255,0.2);
            border-radius: 4px;
            min-width: 40px;
        }
    )");
    
    QWidget* centralWidget = new QWidget(this);
    centralWidget->setStyleSheet("background: transparent;");
    setCentralWidget(centralWidget);
    
    QVBoxLayout* layout = new QVBoxLayout(centralWidget);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);
    
    // Image display area
    m_scrollArea = new QScrollArea(this);
    m_scrollArea->setWidgetResizable(true);
    m_scrollArea->setHorizontalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    m_scrollArea->setVerticalScrollBarPolicy(Qt::ScrollBarAsNeeded);
    m_scrollArea->setAlignment(Qt::AlignCenter);
    m_scrollArea->setStyleSheet("QScrollArea { background: transparent; border: none; }");
    
    m_imageLabel = new QLabel(this);
    m_imageLabel->setAlignment(Qt::AlignCenter);
    m_imageLabel->setStyleSheet("QLabel { background: transparent; border: none; color: rgba(255,255,255,0.6); font-size: 14px; }");
    m_imageLabel->setMinimumSize(100, 100);
    m_imageLabel->setMouseTracking(true);
    m_imageLabel->installEventFilter(this);
    
    m_scrollArea->setWidget(m_imageLabel);
    layout->addWidget(m_scrollArea);
    
    // Download widget for non-image files
    m_downloadWidget = new QWidget(this);
    m_downloadWidget->setStyleSheet("QWidget { background: transparent; }");
    QVBoxLayout* downloadLayout = new QVBoxLayout(m_downloadWidget);
    downloadLayout->setAlignment(Qt::AlignCenter);
    downloadLayout->setSpacing(20);
    
    m_fileInfoLabel = new QLabel(m_downloadWidget);
    m_fileInfoLabel->setAlignment(Qt::AlignCenter);
    m_fileInfoLabel->setStyleSheet("QLabel { color: rgba(255,255,255,0.85); font-size: 16px; font-weight: 500; }");
    downloadLayout->addWidget(m_fileInfoLabel);
    
    m_progressBar = new QProgressBar(m_downloadWidget);
    m_progressBar->setMinimum(0);
    m_progressBar->setMaximum(100);
    m_progressBar->setFixedWidth(300);
    m_progressBar->setFixedHeight(6);
    m_progressBar->setTextVisible(false);
    m_progressBar->setStyleSheet(R"(
        QProgressBar {
            border: none;
            border-radius: 3px;
            background: rgba(255,255,255,0.1);
        }
        QProgressBar::chunk {
            background: #007AFF;
            border-radius: 3px;
        }
    )");
    m_progressBar->hide();
    downloadLayout->addWidget(m_progressBar, 0, Qt::AlignCenter);
    
    QHBoxLayout* btnLayout = new QHBoxLayout();
    btnLayout->setSpacing(12);
    
    QString primaryBtnStyle = R"(
        QPushButton {
            background: #007AFF;
            color: white;
            border: none;
            padding: 10px 24px;
            border-radius: 8px;
            font-size: 13px;
            font-weight: 500;
        }
        QPushButton:hover {
            background: #0056CC;
        }
        QPushButton:disabled {
            background: rgba(255,255,255,0.1);
            color: rgba(255,255,255,0.3);
        }
    )";
    
    QString secondaryBtnStyle = R"(
        QPushButton {
            background: rgba(255,255,255,0.1);
            color: rgba(255,255,255,0.85);
            border: 1px solid rgba(255,255,255,0.15);
            padding: 10px 24px;
            border-radius: 8px;
            font-size: 13px;
            font-weight: 500;
        }
        QPushButton:hover {
            background: rgba(255,255,255,0.15);
        }
    )";
    
    m_downloadButton = new QPushButton("Скачать", m_downloadWidget);
    m_downloadButton->setCursor(Qt::PointingHandCursor);
    m_downloadButton->setStyleSheet(primaryBtnStyle);
    connect(m_downloadButton, &QPushButton::clicked, this, &MediaViewer::onDownloadClicked);
    btnLayout->addWidget(m_downloadButton);
    
    m_showButton = new QPushButton("Показать в папке", m_downloadWidget);
    m_showButton->setCursor(Qt::PointingHandCursor);
    m_showButton->setStyleSheet(secondaryBtnStyle);
    m_showButton->hide();
    connect(m_showButton, &QPushButton::clicked, this, &MediaViewer::onShowClicked);
    btnLayout->addWidget(m_showButton);
    
    m_openFolderButton = new QPushButton("Открыть папку", m_downloadWidget);
    m_openFolderButton->setCursor(Qt::PointingHandCursor);
    m_openFolderButton->setStyleSheet(secondaryBtnStyle);
    connect(m_openFolderButton, &QPushButton::clicked, this, &MediaViewer::onOpenFolderClicked);
    btnLayout->addWidget(m_openFolderButton);
    
    downloadLayout->addLayout(btnLayout);
    
    m_downloadWidget->hide();
    layout->addWidget(m_downloadWidget);
    
    // Loading widget for images
    m_loadingWidget = new QWidget(this);
    m_loadingWidget->setStyleSheet("QWidget { background: transparent; }");
    QVBoxLayout* loadingLayout = new QVBoxLayout(m_loadingWidget);
    loadingLayout->setAlignment(Qt::AlignCenter);
    loadingLayout->setSpacing(16);
    
    m_loadingLabel = new QLabel("Загрузка...", m_loadingWidget);
    m_loadingLabel->setAlignment(Qt::AlignCenter);
    m_loadingLabel->setStyleSheet("QLabel { color: rgba(255,255,255,0.7); font-size: 14px; }");
    loadingLayout->addWidget(m_loadingLabel);
    
    m_imageProgressBar = new QProgressBar(m_loadingWidget);
    m_imageProgressBar->setMinimum(0);
    m_imageProgressBar->setMaximum(100);
    m_imageProgressBar->setFixedWidth(300);
    m_imageProgressBar->setFixedHeight(6);
    m_imageProgressBar->setTextVisible(false);
    m_imageProgressBar->setStyleSheet(R"(
        QProgressBar {
            border: none;
            border-radius: 3px;
            background: rgba(255,255,255,0.1);
        }
        QProgressBar::chunk {
            background: #007AFF;
            border-radius: 3px;
        }
    )");
    loadingLayout->addWidget(m_imageProgressBar, 0, Qt::AlignCenter);
    
    m_loadingWidget->hide();
    layout->addWidget(m_loadingWidget);
    
    m_scrollArea->setHorizontalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    m_scrollArea->setVerticalScrollBarPolicy(Qt::ScrollBarAlwaysOff);
    
    setMouseTracking(true);
}

bool MediaViewer::event(QEvent *event)
{
    return QMainWindow::event(event);
}

void MediaViewer::wheelEvent(QWheelEvent *event)
{
    // Убираем масштабирование - просто игнорируем события колесика/трекпада
    event->ignore();
}

void MediaViewer::keyPressEvent(QKeyEvent *event)
{
    if (event->key() == Qt::Key_Left) {
        previousMedia();
        event->accept();
    } else if (event->key() == Qt::Key_Right) {
        nextMedia();
        event->accept();
    } else if (event->key() == Qt::Key_Escape) {
        close();
        event->accept();
    } else {
        QMainWindow::keyPressEvent(event);
    }
}

void MediaViewer::resizeEvent(QResizeEvent *event)
{
    QMainWindow::resizeEvent(event);
    // Перерисовываем изображение при изменении размера окна
    if (m_movie && m_movie->isValid() && !m_gifOriginalSize.isEmpty()) {
        QSize windowSize = size();
        QSize scaledSize = m_gifOriginalSize.scaled(windowSize, Qt::KeepAspectRatio);
        m_movie->setScaledSize(scaledSize);
        m_imageLabel->resize(scaledSize);
        m_imageLabel->move(
            (windowSize.width() - scaledSize.width()) / 2,
            (windowSize.height() - scaledSize.height()) / 2
        );
    } else if (!m_originalPixmap.isNull()) {
        displayImage(m_originalPixmap);
    }
}

void MediaViewer::displayImage(const QPixmap& pixmap, bool saveOriginal)
{
    if (pixmap.isNull()) return;
    
    if (saveOriginal) {
        m_originalPixmap = pixmap;
    }
    
    // Показываем изображение на всё окно без отступов
    const QPixmap& sourcePixmap = m_originalPixmap.isNull() ? pixmap : m_originalPixmap;
    QSize windowSize = size();
    
    // Масштабируем точно под размер окна
    QPixmap scaledPixmap = sourcePixmap.scaled(
        windowSize.width(), windowSize.height(),
        Qt::KeepAspectRatio, 
        Qt::SmoothTransformation
    );
    
    m_imageLabel->setPixmap(scaledPixmap);
    m_imageLabel->resize(scaledPixmap.size());
    
    // Центрируем изображение (заполняем всё окно)
    m_imageLabel->move(
        (windowSize.width() - scaledPixmap.width()) / 2,
        (windowSize.height() - scaledPixmap.height()) / 2
    );
    
    updateWindowTitle();
}

void MediaViewer::displayFullImage(const QPixmap& pixmap)
{
    displayImage(pixmap, true);
    m_isFullImageLoaded = true;
}

void MediaViewer::displayGif(const QString& filepath)
{
    if (m_movie) {
        m_movie->stop();
        delete m_movie;
        m_movie = nullptr;
    }
    
    m_movie = new QMovie(filepath);
    if (m_movie->isValid()) {
        // Get original GIF size
        m_movie->jumpToFrame(0);
        QSize originalSize = m_movie->currentImage().size();
        m_gifOriginalSize = originalSize;
        
        // Scale GIF to fit window while keeping aspect ratio
        QSize windowSize = size();
        QSize scaledSize = originalSize.scaled(windowSize, Qt::KeepAspectRatio);
        m_movie->setScaledSize(scaledSize);
        
        m_imageLabel->setMovie(m_movie);
        m_imageLabel->resize(scaledSize);
        
        // Center the GIF
        m_imageLabel->move(
            (windowSize.width() - scaledSize.width()) / 2,
            (windowSize.height() - scaledSize.height()) / 2
        );
        
        m_movie->start();
        m_isFullImageLoaded = true;
    } else {
        delete m_movie;
        m_movie = nullptr;
        m_imageLabel->setText("Ошибка загрузки GIF");
    }
}

bool MediaViewer::isImageFormat(const QString& filename) const
{
    QString ext = QFileInfo(filename).suffix().toLower();
    return ext == "jpg" || ext == "jpeg" || ext == "png" || 
           ext == "gif" || ext == "webp" || ext == "bmp" || ext == "tiff";
}

bool MediaViewer::isGifFormat(const QString& filename) const
{
    QString ext = QFileInfo(filename).suffix().toLower();
    return ext == "gif";
}

void MediaViewer::showDownloadUI()
{
    m_scrollArea->hide();
    m_downloadWidget->show();
    
    QString filepath = getCorrectFilepath();
    QFileInfo fileInfo(filepath);
    
    if (fileInfo.exists() && fileInfo.size() > 0) {
        m_downloadButton->hide();
        m_showButton->show();
        m_progressBar->hide();
        m_fileInfoLabel->setText(QString("Файл: %1\nРазмер: %2")
            .arg(fileInfo.fileName())
            .arg(formatFileSize(fileInfo.size())));
    } else {
        m_downloadButton->show();
        m_downloadButton->setEnabled(true);
        m_showButton->hide();
        m_progressBar->hide();
        
        const QVariantMap& currentMedia = m_mediaItems[m_currentIndex];
        QString filename = QFileInfo(currentMedia["filename"].toString()).fileName();
        m_fileInfoLabel->setText(QString("Файл: %1\nТип не поддерживается для просмотра")
            .arg(filename));
    }
}

void MediaViewer::showImageUI()
{
    m_downloadWidget->hide();
    m_loadingWidget->hide();
    m_scrollArea->show();
}

void MediaViewer::showLoadingUI()
{
    m_downloadWidget->hide();
    m_scrollArea->hide();
    m_imageProgressBar->setValue(0);
    m_loadingLabel->setText("Загрузка...");
    m_loadingWidget->show();
}

QString MediaViewer::formatFileSize(qint64 size) const
{
    if (size < 1024) return QString("%1 B").arg(size);
    if (size < 1024 * 1024) return QString("%1 KB").arg(size / 1024.0, 0, 'f', 1);
    if (size < 1024 * 1024 * 1024) return QString("%1 MB").arg(size / (1024.0 * 1024.0), 0, 'f', 2);
    return QString("%1 GB").arg(size / (1024.0 * 1024.0 * 1024.0), 0, 'f', 2);
}

void MediaViewer::onDownloadClicked()
{
    downloadFile();
}

void MediaViewer::onShowClicked()
{
    QString filepath = getCorrectFilepath();
    QFileInfo fileInfo(filepath);
    
    if (fileInfo.exists()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(fileInfo.absolutePath()));
    }
}

void MediaViewer::onOpenFolderClicked()
{
    QString filepath = getCorrectFilepath();
    QFileInfo fileInfo(filepath);
    QString folderPath = fileInfo.absolutePath();
    
    // Если файл не существует, попробуем открыть директорию поста
    if (!fileInfo.exists() && !m_mediaItems.isEmpty()) {
        const QVariantMap& currentMedia = m_mediaItems[m_currentIndex];
        QString authorName = currentMedia.value("author_name").toString();
        QString postId = currentMedia.value("post_id").toString();
        QString postTitle = currentMedia.value("post_title").toString();
        QString service = currentMedia.value("service").toString();
        
        if (!authorName.isEmpty() && !postId.isEmpty()) {
            QString basePath = QDir::currentPath() + "/downloads";
            QString postFolder = QString("%1_%2_%3").arg(service, authorName, postId);
            folderPath = basePath + "/" + postFolder;
            if (!postTitle.isEmpty()) {
                folderPath += "/" + postTitle;
            }
        }
    }
    
    QDir dir(folderPath);
    if (dir.exists()) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(folderPath));
    }
}

void MediaViewer::downloadFile()
{
    if (m_isDownloading) return;
    
    const QVariantMap& currentMedia = m_mediaItems[m_currentIndex];
    QString url = currentMedia["url"].toString();
    
    if (url.isEmpty()) {
        m_fileInfoLabel->setText("Ошибка: пустой URL");
        return;
    }
    
    QString filepath = getCorrectFilepath();
    
    m_isDownloading = true;
    m_downloadButton->setEnabled(false);
    m_downloadButton->setText("Скачивание...");
    m_progressBar->setValue(0);
    m_progressBar->show();
    
    // Используем MediaDownloadManager для синхронизации загрузок
    m_currentDownloadUrl = url;
    MediaDownloadManager* manager = MediaDownloadManager::instance();
    manager->startDownload(url, filepath, this);
}

void MediaViewer::onDownloadProgress(qint64 bytesReceived, qint64 bytesTotal)
{
    // Старый метод для совместимости (не используется при MediaDownloadManager)
    if (bytesTotal > 0) {
        int percent = static_cast<int>((bytesReceived * 100) / bytesTotal);
        if (m_progressBar) {
            m_progressBar->setValue(percent);
        }
        if (m_fileInfoLabel) {
            m_fileInfoLabel->setText(QString("Скачивание: %1 / %2")
                .arg(formatFileSize(bytesReceived))
                .arg(formatFileSize(bytesTotal)));
        }
    }
}

void MediaViewer::onDownloadProgress(const QString& url, qint64 bytesReceived, qint64 bytesTotal)
{
    // Реализация IMediaDownloadSubscriber
    if (bytesTotal > 0) {
        int percent = static_cast<int>((bytesReceived * 100) / bytesTotal);
        if (m_progressBar) {
            m_progressBar->setValue(percent);
        }
        if (m_fileInfoLabel) {
            m_fileInfoLabel->setText(QString("Скачивание: %1 / %2")
                .arg(formatFileSize(bytesReceived))
                .arg(formatFileSize(bytesTotal)));
        }
        if (m_imageProgressBar) {
            m_imageProgressBar->setValue(percent);
        }
    }
}

void MediaViewer::onFileDownloaded()
{
    // Старый метод для совместимости (не используется при MediaDownloadManager)
    m_isDownloading = false;
    
    if (!m_fileDownloadReply) return;
    
    if (m_fileDownloadReply->error() == QNetworkReply::NoError) {
        QByteArray data = m_fileDownloadReply->readAll();
        QString filepath = getCorrectFilepath();
        
        QDir dir = QFileInfo(filepath).dir();
        if (!dir.exists()) {
            dir.mkpath(".");
        }
        
        QFile file(filepath);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(data);
            file.close();
            
            QFileInfo fileInfo(filepath);
            if (m_fileInfoLabel) {
                m_fileInfoLabel->setText(QString("Файл: %1\nРазмер: %2\nСкачано!")
                    .arg(fileInfo.fileName())
                    .arg(formatFileSize(fileInfo.size())));
            }
            
            if (m_downloadButton) m_downloadButton->hide();
            if (m_showButton) m_showButton->show();
            if (m_progressBar) m_progressBar->hide();
        } else {
            if (m_fileInfoLabel) m_fileInfoLabel->setText("Ошибка сохранения файла");
            if (m_downloadButton) {
                m_downloadButton->setEnabled(true);
                m_downloadButton->setText("Скачать");
            }
        }
    } else {
        if (m_fileInfoLabel) {
            m_fileInfoLabel->setText("Ошибка скачивания: " + m_fileDownloadReply->errorString());
        }
        if (m_downloadButton) {
            m_downloadButton->setEnabled(true);
            m_downloadButton->setText("Скачать");
        }
        if (m_progressBar) m_progressBar->hide();
    }
    
    m_fileDownloadReply->deleteLater();
    m_fileDownloadReply = nullptr;
}

void MediaViewer::onDownloadFinished(const QString& url, const QString& filepath, bool success)
{
    // Реализация IMediaDownloadSubscriber
    m_isDownloading = false;
    
    if (success) {
        QFileInfo fileInfo(filepath);
        if (m_fileInfoLabel) {
            m_fileInfoLabel->setText(QString("Файл: %1\nРазмер: %2\nСкачано!")
                .arg(fileInfo.fileName())
                .arg(formatFileSize(fileInfo.size())));
        }
        
        if (m_downloadButton) m_downloadButton->hide();
        if (m_showButton) m_showButton->show();
        if (m_progressBar) m_progressBar->hide();
        if (m_imageProgressBar) m_imageProgressBar->hide();
        if (m_loadingWidget) m_loadingWidget->hide();
        
        // Если это изображение, отображаем его
        const QVariantMap& currentMedia = m_mediaItems[m_currentIndex];
        QString filename = currentMedia["filename"].toString();
        
        if (isImageFormat(filename)) {
            showImageUI();
            if (isGifFormat(filename)) {
                displayGif(filepath);
            } else {
                QPixmap pixmap(filepath);
                if (!pixmap.isNull()) {
                    displayFullImage(pixmap);
                }
            }
        }
    } else {
        if (m_fileInfoLabel) {
            m_fileInfoLabel->setText("Ошибка скачивания");
        }
        if (m_downloadButton) {
            m_downloadButton->setEnabled(true);
            m_downloadButton->setText("Скачать");
        }
        if (m_progressBar) m_progressBar->hide();
        if (m_imageProgressBar) m_imageProgressBar->hide();
    }
}

void MediaViewer::showPreview()
{
    const QVariantMap& currentMedia = m_mediaItems[m_currentIndex];
    QString url = currentMedia["url"].toString();
    
    if (url.isEmpty()) {
        url = currentMedia["preview_url"].toString();
    }
    
    if (url.isEmpty()) {
        m_imageLabel->setText("Загрузка...");
        return;
    }
    
    QString fullUrl = url;
    if (!fullUrl.startsWith("http://") && !fullUrl.startsWith("https://")) {
        if (fullUrl.startsWith("/")) {
            fullUrl = QString("https://kemono.cr%1").arg(fullUrl);
        } else {
            fullUrl = QString("https://kemono.cr/%1").arg(fullUrl);
        }
    }
    
    if (m_cacheManager) {
        QString cachedPath = m_cacheManager->getCachedPreviewPath(fullUrl);
        if (!cachedPath.isEmpty() && QFile::exists(cachedPath)) {
            QPixmap previewPixmap(cachedPath);
            if (!previewPixmap.isNull()) {
                m_previewPixmap = previewPixmap;
                displayImage(previewPixmap, false);
                return;
            }
        }
    }
    
    QNetworkRequest request;
    request.setUrl(QUrl(fullUrl));
    request.setRawHeader("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36");
    request.setRawHeader("Referer", "https://kemono.cr/");
    
    m_previewReply = m_networkManager->get(request);
    if (m_previewReply) {
        connect(m_previewReply, &QNetworkReply::finished, [this, fullUrl]() {
            if (m_previewReply && m_previewReply->error() == QNetworkReply::NoError) {
                QByteArray data = m_previewReply->readAll();
                QPixmap previewPixmap;
                if (previewPixmap.loadFromData(data)) {
                    m_previewPixmap = previewPixmap;
                    displayImage(previewPixmap, false);
                    if (m_cacheManager) {
                        m_cacheManager->cachePreview(fullUrl, previewPixmap);
                    }
                } else {
                    m_imageLabel->setText("Ошибка загрузки");
                }
            } else {
                m_imageLabel->setText("Ошибка загрузки");
            }
            m_previewReply->deleteLater();
            m_previewReply = nullptr;
        });
    } else {
        m_imageLabel->setText("Ошибка");
    }
}

void MediaViewer::loadFullImageAsync()
{
    if (m_currentIndex < 0 || m_currentIndex >= m_mediaItems.size()) {
        return;
    }
    
    const QVariantMap& currentMedia = m_mediaItems[m_currentIndex];
    QString filename = currentMedia["filename"].toString();
    QString filepath = getCorrectFilepath();
    QFileInfo fileInfo(filepath);
    
    // Check if file already downloaded
    if (fileInfo.exists() && fileInfo.size() > 0) {
        showImageUI();
        if (isGifFormat(filename)) {
            displayGif(filepath);
            return;
        } else {
            QPixmap pixmap(filepath);
            if (!pixmap.isNull()) {
                displayFullImage(pixmap);
                return;
            }
        }
    }
    
    QString url = currentMedia["url"].toString();
    
    if (url.isEmpty()) {
        m_loadingLabel->setText("Ошибка: пустой URL");
        return;
    }
    
    QString fullUrl = url;
    if (!fullUrl.startsWith("http://") && !fullUrl.startsWith("https://")) {
        if (fullUrl.startsWith("/")) {
            fullUrl = QString("https://kemono.cr%1").arg(fullUrl);
        } else {
            fullUrl = QString("https://kemono.cr/%1").arg(fullUrl);
        }
    }
    
    // Используем MediaDownloadManager для синхронизации загрузок
    showLoadingUI();
    m_currentDownloadUrl = url;
    MediaDownloadManager* manager = MediaDownloadManager::instance();
    manager->startDownload(url, filepath, this);
}

void MediaViewer::onImageDownloaded()
{
    QNetworkReply* reply = qobject_cast<QNetworkReply*>(sender());
    if (!reply) reply = m_currentReply;
    if (!reply) return;
    
    if (reply->error() == QNetworkReply::NoError) {
        QByteArray data = reply->readAll();
        QString filepath = getCorrectFilepath();
        QDir dir = QFileInfo(filepath).dir();
        if (!dir.exists()) {
            dir.mkpath(".");
        }
        
        const QVariantMap& currentMedia = m_mediaItems[m_currentIndex];
        QString filename = currentMedia["filename"].toString();
        
        // Save file first
        QFile file(filepath);
        if (file.open(QIODevice::WriteOnly)) {
            file.write(data);
            file.close();
        }
        
        // Switch to image UI before displaying
        showImageUI();
        
        // Display based on type
        if (isGifFormat(filename)) {
            displayGif(filepath);
        } else {
            QPixmap pixmap;
            if (pixmap.loadFromData(data)) {
                m_isFullImageLoaded = true;
                displayFullImage(pixmap);
            } else {
                m_imageLabel->setText("Ошибка загрузки");
            }
        }
    } else {
        if (m_loadingLabel) {
            m_loadingLabel->setText("Ошибка сети");
        }
    }
    
    if (reply == m_currentReply) m_currentReply = nullptr;
    reply->deleteLater();
}

void MediaViewer::onNetworkError(QNetworkReply::NetworkError error)
{
    Q_UNUSED(error);
    if (m_currentReply) {
        m_currentReply->deleteLater();
        m_currentReply = nullptr;
    }
}

QString MediaViewer::getCorrectFilepath() const
{
    if (m_currentIndex < 0 || m_currentIndex >= m_mediaItems.size()) {
        return QString();
    }
    
    const QVariantMap& currentMedia = m_mediaItems[m_currentIndex];
    QString filename = QFileInfo(currentMedia["filename"].toString()).fileName();
    QString postTitle = currentMedia["post_title"].toString();
    QString postId = currentMedia["post_id"].toString();
    
    // Получаем информацию об авторе из mediaItem или из родительского окна
    QString authorName = currentMedia["author_name"].toString();
    
    if (authorName.isEmpty()) {
        // Пытаемся получить из родительского окна (MainWindow)
        // Используем QObject::findChild для поиска MainWindow
        QWidget* parent = parentWidget();
        while (parent) {
            // Проверяем имя класса через мета-объектную систему Qt
            if (parent->metaObject()->className() == QLatin1String("MainWindow")) {
                // Используем Q_INVOKABLE метод или получаем через property
                QVariant artistVariant = parent->property("currentArtist");
                if (artistVariant.isValid() && artistVariant.canConvert<Artist>()) {
                    Artist artist = artistVariant.value<Artist>();
                    if (!artist.id().isEmpty()) {
                        authorName = QString("%1_%2_%3")
                            .arg(artist.service())
                            .arg(artist.name())
                            .arg(artist.id());
                        break;
                    }
                }
            }
            parent = parent->parentWidget();
        }
    }
    
    if (authorName.isEmpty()) {
        authorName = "unknown_author";
    }
    
    // Создаем безопасное название поста
    QString safeTitle = postTitle;
    QRegularExpression regex("[<>:\"/\\|?*]");
    safeTitle.replace(regex, "_");
    safeTitle = safeTitle.left(50);
    
    QString postDir = QString("downloads/%1/%2").arg(authorName, safeTitle);
    return QString("%1/%2").arg(postDir, filename);
}

bool MediaViewer::eventFilter(QObject *obj, QEvent *event)
{
    Q_UNUSED(obj);
    Q_UNUSED(event);
    return false;
}

void MediaViewer::mousePressEvent(QMouseEvent *event)
{
    setFocus();
    QMainWindow::mousePressEvent(event);
}

void MediaViewer::mouseMoveEvent(QMouseEvent *event)
{
    QMainWindow::mouseMoveEvent(event);
}

void MediaViewer::mouseReleaseEvent(QMouseEvent *event)
{
    QMainWindow::mouseReleaseEvent(event);
}

void MediaViewer::loadCurrentMedia()
{
    if (m_currentIndex < 0 || m_currentIndex >= m_mediaItems.size()) {
        return;
    }
    
    // Stop any GIF animation
    if (m_movie) {
        m_movie->stop();
        delete m_movie;
        m_movie = nullptr;
    }
    m_gifOriginalSize = QSize();
    
    m_originalPixmap = QPixmap();
    m_previewPixmap = QPixmap();
    m_isFullImageLoaded = false;
    m_isDownloading = false;
    
    if (m_currentReply) {
        m_currentReply->abort();
        m_currentReply = nullptr;
    }
    if (m_previewReply) {
        m_previewReply->abort();
        m_previewReply = nullptr;
    }
    if (m_fileDownloadReply) {
        m_fileDownloadReply->abort();
        m_fileDownloadReply = nullptr;
    }
    
    const QVariantMap& currentMedia = m_mediaItems[m_currentIndex];
    QString filename = currentMedia["filename"].toString();
    QString filepath = getCorrectFilepath();
    QFileInfo fileInfo(filepath);
    
    updateWindowTitle();
    
    if (isImageFormat(filename)) {
        // Check if already downloaded - load directly
        if (fileInfo.exists() && fileInfo.size() > 0) {
            showImageUI();
            if (isGifFormat(filename)) {
                displayGif(filepath);
            } else {
                QPixmap pixmap;
                if (pixmap.load(filepath)) {
                    displayFullImage(pixmap);
                } else {
                    m_imageLabel->setText("Ошибка чтения файла");
                }
            }
        } else {
            // Not downloaded - show loading indicator with progress bar
            showLoadingUI();
            loadFullImageAsync();
        }
    } else {
        showDownloadUI();
    }
}

void MediaViewer::nextMedia()
{
    if (m_currentIndex < m_mediaItems.size() - 1) {
        m_currentIndex++;
        loadCurrentMedia();
    }
}

void MediaViewer::previousMedia()
{
    if (m_currentIndex > 0) {
        m_currentIndex--;
        loadCurrentMedia();
    }
}

void MediaViewer::updateWindowTitle()
{
    if (m_currentIndex >= 0 && m_currentIndex < m_mediaItems.size()) {
        const QVariantMap& currentMedia = m_mediaItems[m_currentIndex];
        QString filename = QFileInfo(currentMedia["filename"].toString()).fileName();
        setWindowTitle(QString("Просмотр: %1 [%2/%3]")
                       .arg(filename)
                       .arg(m_currentIndex + 1)
                       .arg(m_mediaItems.size()));
    }
}

