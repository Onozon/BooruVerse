#ifndef POSTVIEWER_H
#define POSTVIEWER_H

#include <QMainWindow>
#include <QScrollArea>
#include <QGridLayout>
#include <QVBoxLayout>
#include <QWidget>
#include <QLabel>
#include <QPushButton>
#include <QCheckBox>
#include <QProgressBar>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QFileInfo>
#include <QMap>
#include <QQueue>
#include <QCloseEvent>
#include <QEvent>
#include "models/post.h"
#include "cache/cachemanager.h"
#include "core/mediadownloadmanager.h"

// Структура для элемента очереди загрузки
struct DownloadQueueItem {
    QString url;
    QString filepath;
    QProgressBar* progressBar;
    QLabel* previewLabel;
    bool isImage;
};

class PostViewer : public QMainWindow, public IMediaDownloadSubscriber
{
    Q_OBJECT

public:
    explicit PostViewer(const Post& post, CacheManager* cacheManager, QWidget *parent = nullptr);
    ~PostViewer();

signals:
    void mediaClicked(const QVariantMap& mediaItem);
    void openAuthorRequested(const QString& service, const QString& userId, const QString& authorName);

protected:
    void closeEvent(QCloseEvent* event) override;
    bool eventFilter(QObject* obj, QEvent* event) override;

private slots:
    void onMediaClicked(const QVariantMap& mediaItem);
    void onRetryClicked();
    void onOpenFolderClicked();

    // IMediaDownloadSubscriber interface
    void onDownloadProgress(const QString& url, qint64 bytesReceived, qint64 bytesTotal) override;
    void onDownloadFinished(const QString& url, const QString& filepath, bool success) override;

private:
    void setupUI();
    void loadPostMedia();
    void loadMediaPreview(QLabel* label, QWidget* mediaWidget, const QString& mediaUrl, const QString& filename);
    void showRetryButton(QLabel* label, QWidget* mediaWidget, const QString& mediaUrl, const QString& filename);
    void downloadMediaFile(const QString& url, const QString& filepath, 
                          QProgressBar* progressBar = nullptr, QLabel* previewLabel = nullptr, bool isImage = false);
    void queueDownload(const QString& url, const QString& filepath, 
                      QProgressBar* progressBar, QLabel* previewLabel, bool isImage);
    void processDownloadQueue();
    void onDownloadFinished(const QString& url);
    void cancelAllDownloads();
    QString getMediaFilepath(const QString& filename) const;
    bool isImageFormat(const QString& filename) const;
    
    Post m_post;
    CacheManager* m_cacheManager;
    QScrollArea* m_scrollArea;
    QWidget* m_container;
    QGridLayout* m_mediaLayout;
    QList<QVariantMap> m_mediaItems;
    QNetworkAccessManager* m_networkManager;
    // Map для хранения информации о повторных попытках: label -> (url, filename, widget)
    QMap<QLabel*, QPair<QPair<QString, QString>, QWidget*>> m_retryInfo;
    // Map для отслеживания загрузок: url -> filepath
    QMap<QString, QString> m_downloadingFiles;
    // Map для прогресс-баров: url -> progressBar
    QMap<QString, QProgressBar*> m_progressBars;
    // Map для preview labels: url -> label
    QMap<QString, QLabel*> m_previewLabels;
    // Очередь загрузок (используется для последовательной обработки, но без лимита)
    QQueue<DownloadQueueItem> m_downloadQueue;
    // Активные reply для отмены
    QList<QNetworkReply*> m_activeReplies;
    // Флаг закрытия окна
    bool m_isClosing;
};

#endif // POSTVIEWER_H

