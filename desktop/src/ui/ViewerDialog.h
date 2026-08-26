#pragma once

#include "core/Models.h"

#include <QDialog>
#include <QPixmap>
#include <QVector>

class QLabel;
class QListWidget;
class QProgressBar;
class QPushButton;
class QScrollArea;

class ViewerDialog : public QDialog {
    Q_OBJECT
public:
    explicit ViewerDialog(QWidget *parent = nullptr);

    void showPosts(const QVector<BooruPost> &posts, int index);
    void appendPosts(const QVector<BooruPost> &posts);
    int currentIndex() const { return m_index; }

signals:
    void tagClicked(const QString &tag);
    void nearEnd();
    void currentChanged(int index);

protected:
    void keyPressEvent(QKeyEvent *event) override;
    void wheelEvent(QWheelEvent *event) override;
    void resizeEvent(QResizeEvent *event) override;

private:
    void loadCurrent(bool preferOriginal = false);
    void applyPixmap();
    void moveBy(int delta);
    void refreshChrome();
    void toggleFavorite();
    void saveCurrent();
    void openSite();
    void openSource();

    QScrollArea *m_scroll = nullptr;
    QLabel *m_image = nullptr;
    QLabel *m_meta = nullptr;
    QListWidget *m_tags = nullptr;
    QProgressBar *m_progress = nullptr;
    QPushButton *m_favorite = nullptr;
    QVector<BooruPost> m_posts;
    int m_index = 0;
    QPixmap m_pixmap;
    double m_scale = 1.0;
    int m_generation = 0;
};
