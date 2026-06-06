#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>
#include <QWidget>
#include <QVBoxLayout>
#include <QHBoxLayout>
#include <QLineEdit>
#include <QPushButton>
#include <QListWidget>
#include <QTextEdit>
#include <QProgressBar>
#include <QTabWidget>
#include <QLabel>
#include <QList>
#include <QGridLayout>
#include <QCheckBox>
#include <QGroupBox>
#include <QMenuBar>
#include <QMenu>
#include <QThread>
#include <QJsonObject>
#include <QAction>
#include <QScrollArea>
#include <QComboBox>
#include <QSplitter>
#include <QFrame>
#include <QEvent>
#include <QMouseEvent>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QMap>
#include <QQueue>
#include <QCloseEvent>
#include <functional>
#include "parser/kemonoparser.h"
#include "models/artist.h"
#include "models/post.h"
#include "cache/cachemanager.h"
#include "gui/mediaviewer.h"
#include "gui/postviewer.h"
#include "gui/sectionstate.h"
#include "gui/historymanager.h"
#include "core/mediadownloadmanager.h"

class ImageProcessor;

class ArtistClickFilter : public QObject
{
    Q_OBJECT
public:
    ArtistClickFilter(const Artist& artist, QObject* parent, std::function<void()> callback)
        : QObject(parent), m_artist(artist), m_callback(callback) {}
    
protected:
    bool eventFilter(QObject* obj, QEvent* event) override {
        if (event->type() == QEvent::MouseButtonPress) {
            QMouseEvent* mouseEvent = static_cast<QMouseEvent*>(event);
            if (mouseEvent->button() == Qt::LeftButton) {
                m_callback();
                return true;
            }
        }
        return QObject::eventFilter(obj, event);
    }
    
private:
    Artist m_artist;
    std::function<void()> m_callback;
};

class MainWindow : public QMainWindow, public IMediaDownloadSubscriber
{
    Q_OBJECT

public:
    explicit MainWindow(QWidget *parent = nullptr);
    ~MainWindow();

protected:
    void closeEvent(QCloseEvent* event) override;
    bool eventFilter(QObject* obj, QEvent* event) override;

private slots:
    void onArtistsFound(const QList<Artist>& artists);
    void onAllArtistsLoaded(const QList<Artist>& artists);
    void onPopularArtistsLoaded(const QList<Artist>& artists);
    void onRecentlyUpdatedArtistsLoaded(const QList<Artist>& artists);
    void onRandomArtistLoaded(const Artist& artist);
    void onPostsFound(const QList<Post>& posts);
    void onAllArtistPostsLoaded(const QList<Post>& posts, const Artist& artist);
    void onSearchPostsFound(const QList<Post>& posts);
    void onPopularPostsLoaded(const QList<Post>& posts);
    void onRecentPostsLoaded(const QList<Post>& posts);
    void onRandomPostLoaded(const Post& post);
    void onPostLoaded(const Post& post);
    void onError(const QString& error);
    void onArtistItemClicked(QListWidgetItem* item);
    void onPostItemClicked(QListWidgetItem* item);
    void onOpenMediaViewer(const QVariantMap& mediaItem);
    void onOpenAuthorFromViewer(const QString& service, const QString& userId, const QString& authorName);
    void onLoadMoreArtists(int sectionIndex = 0);

private:
    void setupUI();
    void setupConnections();
    void setupMenu();
    void setupSidebar();
    void setupSection(const QString& sectionName, int sectionIndex);
    void setupArtistsTab(int sectionIndex);
    void setupPostsTab(int sectionIndex);
    
    void switchToSection(int sectionIndex, int tabIndex = -1);
    void switchToTab(int sectionIndex, int tabIndex);
    void onSectionTabChanged(int sectionIndex, int tabIndex);
    void updateSidebarHighlighting(int sectionIndex, int tabIndex);
    void onArtistSelected(int sectionIndex, const Artist& artist);
    void onPostSelected(int sectionIndex, const Post& post);
    
    void displayArtistsInSection(int sectionIndex, const QList<Artist>& artists);
    void displayPostsInSection(int sectionIndex, const QList<Post>& posts);
    void clearSectionContent(int sectionIndex, int tabIndex);
    
    void loadArtistsFromCacheOrServer();
    void updateArtistsList();
    void updateArtistPosts(const Artist& artist);
    void performLocalSearch(const QString& query, int offset, int sectionIndex = 0);
    
    void loadPostMedia(const Post& post);
    void loadPostPreviewsInBackground(const QList<Post>& posts);
    void displayArtistButton(const Artist& artist, QGridLayout* layout, int row, int col, int sectionIndex = -1);
    void loadArtistAvatar(QLabel* label, const QString& avatarUrl);
    void loadArtistBanner(QLabel* label, const QString& bannerUrl);
    void loadPostThumbnail(QLabel* label, const QString& thumbnailUrl);
    void loadPostThumbnailLarge(QLabel* label, const QString& thumbnailUrl, int width, int height);
    void queueThumbnailDownload(QLabel* label, QProgressBar* progressBar, const QString& url, int width, int height);
    void processThumbnailQueue();
    void downloadThumbnail(const QString& url, QLabel* label, QProgressBar* progressBar, int width, int height);
    void onThumbnailDownloadFinished(const QString& url);
    void clearThumbnailQueue();
    void cleanupMemory();
    void clearOtherSectionsData(int currentSection);
    void showThumbnailRetryButton(QLabel* label, const QString& thumbnailUrl);
    void onThumbnailRetryClicked();
    void loadMediaPreview(QLabel* label, const QString& mediaUrl, const QString& filename);
    void onMediaPreviewLoaded();
    void onImageProcessed(const QPixmap& scaledPixmap, const QString& url);
    void onImageProcessingFailed(const QString& url);
    
    // IMediaDownloadSubscriber interface
    void onDownloadProgress(const QString& url, qint64 bytesReceived, qint64 bytesTotal) override;
    void onDownloadFinished(const QString& url, const QString& filepath, bool success) override;

    // UI - Main
    QWidget* m_centralWidget;
    QHBoxLayout* m_mainLayout;
    QWidget* m_sidebar;
    QVBoxLayout* m_sidebarLayout;
    QWidget* m_contentArea;
    QVBoxLayout* m_contentLayout;
    
    // Sections: 0=Поиск, 1=История, 2=Оффлайн
    QList<SectionState> m_sectionStates;
    QList<QWidget*> m_sectionWidgets;
    QList<QTabWidget*> m_sectionTabs;
    QList<QWidget*> m_artistsTabs;
    QList<QWidget*> m_postsTabs;
    QList<QLabel*> m_authorNameLabels; // Labels showing current author name in posts tab
    QList<QScrollArea*> m_artistsScrollAreas;
    QList<QWidget*> m_artistsContainers;
    QList<QGridLayout*> m_artistsLayouts;
    QList<QWidget*> m_artistsPaginationWidgets;
    QList<QLabel*> m_artistsPageLabels;
    QList<QScrollArea*> m_postsScrollAreas;
    QList<QWidget*> m_postsContainers;
    QList<QGridLayout*> m_postsLayouts;
    QList<QWidget*> m_postsPaginationWidgets;
    QList<QLabel*> m_postsPageLabels;
    
    QList<QLineEdit*> m_searchInputs;
    QList<QPushButton*> m_searchButtons;
    QList<QPushButton*> m_loadMoreButtons;
    QList<QList<QPushButton*>> m_sidebarButtons;
    
    int m_currentSection = 0;
    int m_currentTab = 0;
    
    bool m_isSwitchingSection = false;
    bool m_isDisplayingPosts = false;
    int m_pendingSectionIndex = -1;
    int m_pendingTabIndex = -1;
    Post m_pendingPostToOpen;
    bool m_hasPendingPost = false;
    
    // Legacy UI for loadPostMedia
    QWidget* m_mediaContainer;
    QGridLayout* m_mediaLayout;
    QTextEdit* m_postContent;
    
    QProgressBar* m_progressBar;
    QLabel* m_statusLabel;

    KemonoParser* m_parser;
    Artist m_currentArtist;
    QList<Post> m_posts;
    
    Q_PROPERTY(Artist currentArtist READ currentArtist)
    Artist currentArtist() const { return m_currentArtist; }
    
    CacheManager* m_cacheManager;
    HistoryManager* m_historyManager;
    
    QList<QVariantMap> m_currentMedia;
    QList<QCheckBox*> m_mediaCheckboxes;
    
    QNetworkAccessManager* m_mediaNetworkManager;
    QMap<QNetworkReply*, QLabel*> m_mediaPreviewReplies;
    QMap<QNetworkReply*, QString> m_mediaPreviewUrls;
    QMap<QString, QLabel*> m_processingLabels;
    QMap<QLabel*, QString> m_thumbnailRetryInfo;
    
    // Post thumbnail download queue system
    struct ThumbnailQueueItem {
        QString url;
        QLabel* previewLabel;
        QProgressBar* progressBar;
        int width;
        int height;
    };
    QQueue<ThumbnailQueueItem> m_thumbnailQueue;
    QMap<QString, QProgressBar*> m_thumbnailProgressBars;
    QMap<QString, QLabel*> m_thumbnailLabels;
    QList<QNetworkReply*> m_activeThumbnailReplies;
    
    // MediaDownloadManager integration for previews/avatars
    enum PreviewType {
        PreviewType_Avatar,
        PreviewType_Banner,
        PreviewType_Thumbnail,
        PreviewType_ThumbnailLarge
    };
    struct PreviewDownloadInfo {
        QLabel* label;
        QProgressBar* progressBar;
        int width;
        int height;
        PreviewType type;
    };
    QMap<QString, PreviewDownloadInfo> m_previewDownloads; // url -> info
    
    QThread* m_imageProcessorThread;
    ImageProcessor* m_imageProcessor;
    
    bool m_isDownloading;
    QString m_downloadPath;
    
    bool m_isAppendingArtists;
    QString m_lastSearchQuery;
    QList<Artist> m_allSearchArtists;
    QList<Artist> m_allCachedArtists;
    int m_artistsSearchOffset;
    
    QMenuBar* m_menuBar;
    QMenu* m_fileMenu;
    QMenu* m_toolsMenu;
};

#endif // MAINWINDOW_H
