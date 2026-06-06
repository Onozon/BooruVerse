#ifndef MEDIAVIEWER_H
#define MEDIAVIEWER_H

#include <QMainWindow>
#include <QScrollArea>
#include <QLabel>
#include <QPixmap>
#include <QMouseEvent>
#include <QWheelEvent>
#include <QKeyEvent>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QString>
#include <QVariantMap>
#include <QPushButton>
#include <QMovie>
#include <QProgressBar>
#include "core/mediadownloadmanager.h"

class CacheManager;

class MediaViewer : public QMainWindow, public IMediaDownloadSubscriber
{
    Q_OBJECT

public:
    explicit MediaViewer(const QList<QVariantMap>& mediaItems, int currentIndex, CacheManager* cacheManager = nullptr, QWidget *parent = nullptr);
    ~MediaViewer();

protected:
    void wheelEvent(QWheelEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;
    bool event(QEvent *event) override;
    bool eventFilter(QObject *obj, QEvent *event) override;
    void mousePressEvent(QMouseEvent *event) override;
    void mouseMoveEvent(QMouseEvent *event) override;
    void mouseReleaseEvent(QMouseEvent *event) override;

private slots:
    void onImageDownloaded();
    void onNetworkError(QNetworkReply::NetworkError error);
    void onDownloadClicked();
    void onShowClicked();
    void onOpenFolderClicked();
    void onDownloadProgress(qint64 bytesReceived, qint64 bytesTotal);
    void onFileDownloaded();

    // IMediaDownloadSubscriber interface
    void onDownloadProgress(const QString& url, qint64 bytesReceived, qint64 bytesTotal) override;
    void onDownloadFinished(const QString& url, const QString& filepath, bool success) override;

private:
    void setupUI();
    void displayImage(const QPixmap& pixmap, bool saveOriginal = false);
    void displayFullImage(const QPixmap& pixmap);
    void displayGif(const QString& filepath);
    void showPreview();
    void loadFullImageAsync();
    QString getCorrectFilepath() const;
    bool isImageFormat(const QString& filename) const;
    bool isGifFormat(const QString& filename) const;
    void showDownloadUI();
    void showImageUI();
    void showLoadingUI();
    void downloadFile();
    
    void loadCurrentMedia();
    void nextMedia();
    void previousMedia();
    void updateWindowTitle();
    QString formatFileSize(qint64 size) const;

    QList<QVariantMap> m_mediaItems;
    int m_currentIndex;
    QPixmap m_originalPixmap;
    QPixmap m_previewPixmap;
    QScrollArea* m_scrollArea;
    QLabel* m_imageLabel;
    QNetworkAccessManager* m_networkManager;
    QNetworkReply* m_currentReply;
    QNetworkReply* m_previewReply;
    QNetworkReply* m_fileDownloadReply;
    CacheManager* m_cacheManager;
    bool m_isFullImageLoaded;
    
    // For non-image files
    QWidget* m_downloadWidget;
    QPushButton* m_downloadButton;
    QPushButton* m_showButton;
    QPushButton* m_openFolderButton;
    QProgressBar* m_progressBar;
    QLabel* m_fileInfoLabel;
    QMovie* m_movie;
    QSize m_gifOriginalSize;
    bool m_isDownloading;
    
    // Loading indicator for images
    QWidget* m_loadingWidget;
    QProgressBar* m_imageProgressBar;
    QLabel* m_loadingLabel;
    
    // Текущий URL для отписки от загрузок
    QString m_currentDownloadUrl;
};

#endif // MEDIAVIEWER_H
