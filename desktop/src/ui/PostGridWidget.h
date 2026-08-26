#pragma once

#include "core/Models.h"

#include <QScrollArea>
#include <QVector>

class ThumbnailCache;
class QGridLayout;

class PostGridWidget : public QScrollArea {
    Q_OBJECT
public:
    explicit PostGridWidget(ThumbnailCache *cache, QWidget *parent = nullptr);

    void setPosts(const QVector<BooruPost> &posts, int restoreScroll = -1);
    void appendPosts(const QVector<BooruPost> &posts);
    void clear();
    void setTileExtent(int extent);
    void setTilingMode(TilingMode mode);
    int tileExtent() const { return m_extent; }
    int scrollValue() const;
    void setScrollValue(int value);
    int selectedIndex() const { return m_selected; }
    void setSelectedIndex(int index);
    QVector<BooruPost> posts() const { return m_posts; }

signals:
    void postActivated(int index);
    void nearBottom();
    void scaleChanged(int extent);
    void favoriteRequested(int index);
    void saveRequested(int index);
    void openSiteRequested(int index);
    void openSourceRequested(int index);

protected:
    void resizeEvent(QResizeEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void keyPressEvent(QKeyEvent *event) override;
    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    void rebuild();
    void refreshSelection();
    int columnCount() const;
    int tileWidth() const;
    QWidget *makeCell(int index);

    ThumbnailCache *m_cache = nullptr;
    QWidget *m_content = nullptr;
    QGridLayout *m_layout = nullptr;
    QVector<BooruPost> m_posts;
    int m_lastColumns = 0;
    int m_extent = 160;
    int m_selected = -1;
    TilingMode m_mode = TilingMode::Columns;
};
