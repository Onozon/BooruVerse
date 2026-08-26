#include "ui/PostGridWidget.h"

#include "core/GallerySettings.h"
#include "core/ServerStore.h"
#include "ui/ThumbnailCache.h"

#include <QContextMenuEvent>
#include <QCursor>
#include <QEvent>
#include <QGridLayout>
#include <QKeyEvent>
#include <QLabel>
#include <QMenu>
#include <QResizeEvent>
#include <QScrollBar>
#include <QTimer>
#include <QVBoxLayout>
#include <QWheelEvent>

static const char kIndexProp[] = "postIndex";
static const char kUrlProp[] = "previewUrl";

PostGridWidget::PostGridWidget(ThumbnailCache *cache, QWidget *parent)
    : QScrollArea(parent)
    , m_cache(cache) {
    setWidgetResizable(true);
    setFrameShape(QFrame::NoFrame);
    setFocusPolicy(Qt::StrongFocus);
    m_content = new QWidget;
    m_layout = new QGridLayout(m_content);
    m_layout->setContentsMargins(16, 16, 16, 16);
    m_layout->setHorizontalSpacing(10);
    m_layout->setVerticalSpacing(12);
    setWidget(m_content);
    verticalScrollBar()->installEventFilter(this);
    connect(verticalScrollBar(), &QScrollBar::valueChanged, this, [this](int value) {
        QScrollBar *bar = verticalScrollBar();
        if (bar->maximum() > 0 && value > bar->maximum() - 240)
            emit nearBottom();
    });
    connect(m_cache, &ThumbnailCache::ready, this, [this](const QUrl &url, const QPixmap &pixmap) {
        const auto labels = m_content->findChildren<QLabel *>();
        for (QLabel *label : labels) {
            if (label->property(kUrlProp).toUrl() == url) {
                label->setPixmap(pixmap.scaled(label->size(), Qt::KeepAspectRatio, Qt::SmoothTransformation));
            }
        }
    });
}

void PostGridWidget::setPosts(const QVector<BooruPost> &posts, int restoreScroll) {
    m_posts = posts;
    m_selected = m_posts.isEmpty() ? -1 : qBound(0, m_selected, m_posts.size() - 1);
    rebuild();
    if (restoreScroll >= 0) {
        const int value = restoreScroll;
        QTimer::singleShot(0, this, [this, value]() { verticalScrollBar()->setValue(value); });
    } else {
        verticalScrollBar()->setValue(0);
    }
}

void PostGridWidget::appendPosts(const QVector<BooruPost> &posts) {
    if (posts.isEmpty())
        return;
    const int start = m_posts.size();
    m_posts += posts;
    if (m_lastColumns <= 0)
        m_lastColumns = columnCount();
    const int columns = qMax(m_lastColumns, 1);
    for (int i = start; i < m_posts.size(); ++i)
        m_layout->addWidget(makeCell(i), i / columns, i % columns);
}

void PostGridWidget::clear() {
    m_posts.clear();
    m_selected = -1;
    rebuild();
}

int PostGridWidget::scrollValue() const {
    return verticalScrollBar()->value();
}

void PostGridWidget::setScrollValue(int value) {
    QTimer::singleShot(0, this, [this, value]() { verticalScrollBar()->setValue(value); });
}

void PostGridWidget::setSelectedIndex(int index) {
    if (m_posts.isEmpty()) {
        m_selected = -1;
        return;
    }
    m_selected = qBound(0, index, m_posts.size() - 1);
    refreshSelection();
}

void PostGridWidget::setTileExtent(int extent) {
    const int snapped = GallerySettings::snap(extent);
    if (m_extent == snapped)
        return;
    m_extent = snapped;
    rebuild();
}

void PostGridWidget::setTilingMode(TilingMode mode) {
    if (m_mode == mode)
        return;
    m_mode = mode;
    rebuild();
}

int PostGridWidget::tileWidth() const {
    if (m_mode == TilingMode::Adaptive)
        return qMax(m_extent - 22, 72);
    return m_extent;
}

int PostGridWidget::columnCount() const {
    const int width = qMax(viewport()->width() - 32, 72);
    return qBound(1, width / qMax(tileWidth(), 72), 10);
}

void PostGridWidget::rebuild() {
    QLayoutItem *item = nullptr;
    while ((item = m_layout->takeAt(0))) {
        delete item->widget();
        delete item;
    }

    m_lastColumns = columnCount();
    const int columns = qMax(m_lastColumns, 1);
    for (int i = 0; i < m_posts.size(); ++i)
        m_layout->addWidget(makeCell(i), i / columns, i % columns);
}

QWidget *PostGridWidget::makeCell(int index) {
    const BooruPost &post = m_posts[index];
    auto *cell = new QWidget;
    cell->setCursor(Qt::PointingHandCursor);
    cell->setProperty(kIndexProp, index);
    auto *box = new QVBoxLayout(cell);
    box->setContentsMargins(0, 0, 0, 0);
    box->setSpacing(6);

    const int width = tileWidth();
    const int height = m_mode == TilingMode::Adaptive ? m_extent : qMax(int(width * 0.75), 100);

    auto *image = new QLabel;
    image->setAlignment(Qt::AlignCenter);
    image->setMinimumHeight(height);
    image->setSizePolicy(QSizePolicy::Expanding, QSizePolicy::Expanding);
    image->setProperty(kUrlProp, post.previewUrl);
    QString style = QStringLiteral("background:#1c1c1e; border-radius:8px;");
    const QColor border = ServerStore::instance().colorFor(post.serverId);
    if (border.isValid() && ServerStore::instance().enabledServers().size() > 1)
        style += QStringLiteral(" border:2px solid %1;").arg(border.name());
    image->setStyleSheet(style);
    const QSize thumb(width, height);
    if (const QPixmap cached = m_cache->cached(post.previewUrl); !cached.isNull())
        image->setPixmap(cached.scaled(thumb, Qt::KeepAspectRatio, Qt::SmoothTransformation));
    else
        m_cache->request(post.previewUrl);

    QString captionText = QStringLiteral("#%1  %2").arg(post.id).arg(post.score);
    if (post.duplicateCount > 1)
        captionText += QStringLiteral("  ×%1").arg(post.duplicateCount);
    auto *caption = new QLabel(captionText);
    caption->setStyleSheet(QStringLiteral("color:#8e8e93; font-size:11px;"));

    box->addWidget(image);
    box->addWidget(caption);
    cell->installEventFilter(this);
    cell->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(cell, &QWidget::customContextMenuRequested, this, [this, index](const QPoint &) {
        m_selected = index;
        refreshSelection();
        QMenu menu(this);
        menu.addAction(QStringLiteral("Open"), this, [this, index]() { emit postActivated(index); });
        menu.addAction(QStringLiteral("Favorite"), this, [this, index]() { emit favoriteRequested(index); });
        menu.addAction(QStringLiteral("Save"), this, [this, index]() { emit saveRequested(index); });
        menu.addAction(QStringLiteral("Open on site"), this, [this, index]() { emit openSiteRequested(index); });
        menu.addAction(QStringLiteral("Open source"), this, [this, index]() { emit openSourceRequested(index); });
        menu.exec(QCursor::pos());
    });
    return cell;
}

void PostGridWidget::refreshSelection() {
    const auto cells = m_content->findChildren<QWidget *>();
    for (QWidget *cell : cells) {
        const QVariant index = cell->property(kIndexProp);
        if (!index.isValid())
            continue;
        cell->setStyleSheet(index.toInt() == m_selected
                                ? QStringLiteral("background:#dbeafe; border-radius:8px;")
                                : QString());
    }
}

void PostGridWidget::resizeEvent(QResizeEvent *event) {
    QScrollArea::resizeEvent(event);
    if (columnCount() != m_lastColumns)
        rebuild();
}

void PostGridWidget::wheelEvent(QWheelEvent *event) {
    if (event->modifiers() & Qt::ControlModifier) {
        const int delta = event->angleDelta().y() > 0 ? 28 : -28;
        setTileExtent(m_extent + delta);
        emit scaleChanged(m_extent);
        event->accept();
        return;
    }
    QScrollArea::wheelEvent(event);
}

void PostGridWidget::keyPressEvent(QKeyEvent *event) {
    if (m_posts.isEmpty()) {
        QScrollArea::keyPressEvent(event);
        return;
    }
    const int columns = qMax(columnCount(), 1);
    if (m_selected < 0)
        m_selected = 0;
    switch (event->key()) {
    case Qt::Key_Left:
        setSelectedIndex(m_selected - 1);
        break;
    case Qt::Key_Right:
        setSelectedIndex(m_selected + 1);
        break;
    case Qt::Key_Up:
        setSelectedIndex(m_selected - columns);
        break;
    case Qt::Key_Down:
        setSelectedIndex(m_selected + columns);
        break;
    case Qt::Key_Return:
    case Qt::Key_Enter:
        emit postActivated(m_selected);
        break;
    case Qt::Key_F:
        emit favoriteRequested(m_selected);
        break;
    case Qt::Key_S:
        emit saveRequested(m_selected);
        break;
    default:
        QScrollArea::keyPressEvent(event);
        return;
    }
    event->accept();
}

bool PostGridWidget::eventFilter(QObject *watched, QEvent *event) {
    if (event->type() == QEvent::MouseButtonRelease) {
        if (auto *widget = qobject_cast<QWidget *>(watched)) {
            const QVariant index = widget->property(kIndexProp);
            if (index.isValid()) {
                m_selected = index.toInt();
                refreshSelection();
                emit postActivated(index.toInt());
                return true;
            }
        }
    }
    return QScrollArea::eventFilter(watched, event);
}
