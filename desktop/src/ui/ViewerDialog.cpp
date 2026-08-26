#include "ui/ViewerDialog.h"

#include "core/FavoriteStore.h"
#include "core/GallerySettings.h"
#include "core/HttpClient.h"
#include "core/ServerStore.h"
#include "core/TagIndexStore.h"

#include <QDesktopServices>
#include <QFile>
#include <QFileDialog>
#include <QHBoxLayout>
#include <QKeyEvent>
#include <QLabel>
#include <QListWidget>
#include <QMessageBox>
#include <QProgressBar>
#include <QPushButton>
#include <QScrollArea>
#include <QShortcut>
#include <QSplitter>
#include <QVBoxLayout>
#include <QWheelEvent>

ViewerDialog::ViewerDialog(QWidget *parent)
    : QDialog(parent) {
    setWindowTitle(QStringLiteral("Viewer"));
    resize(1180, 780);
    setStyleSheet(QStringLiteral("background:#000; color:#fff;"));

    auto *root = new QVBoxLayout(this);
    root->setContentsMargins(0, 0, 0, 0);

    auto *splitter = new QSplitter(Qt::Horizontal);
    m_scroll = new QScrollArea;
    m_scroll->setWidgetResizable(true);
    m_scroll->setAlignment(Qt::AlignCenter);
    m_scroll->setFrameShape(QFrame::NoFrame);
    m_image = new QLabel;
    m_image->setAlignment(Qt::AlignCenter);
    m_scroll->setWidget(m_image);
    splitter->addWidget(m_scroll);

    auto *side = new QWidget;
    side->setMinimumWidth(200);
    side->setMaximumWidth(280);
    auto *sideBox = new QVBoxLayout(side);
    sideBox->setContentsMargins(10, 10, 10, 10);
    auto *tagTitle = new QLabel(QStringLiteral("Tags"));
    tagTitle->setStyleSheet(QStringLiteral("color:#8e8e93;"));
    m_tags = new QListWidget;
    m_tags->setStyleSheet(QStringLiteral("background:#111; border:none;"));
    sideBox->addWidget(tagTitle);
    sideBox->addWidget(m_tags, 1);
    splitter->addWidget(side);
    splitter->setStretchFactor(0, 1);
    splitter->setSizes({900, 220});
    root->addWidget(splitter, 1);

    m_progress = new QProgressBar;
    m_progress->setRange(0, 100);
    m_progress->setTextVisible(false);
    m_progress->setFixedHeight(4);
    m_progress->hide();
    root->addWidget(m_progress);

    auto *bar = new QWidget;
    bar->setStyleSheet(QStringLiteral("background:#111;"));
    auto *row = new QHBoxLayout(bar);
    m_meta = new QLabel;
    m_favorite = new QPushButton(QStringLiteral("Favorite"));
    auto *save = new QPushButton(QStringLiteral("Save"));
    auto *full = new QPushButton(QStringLiteral("Full quality"));
    auto *site = new QPushButton(QStringLiteral("Site"));
    auto *source = new QPushButton(QStringLiteral("Source"));
    auto *close = new QPushButton(QStringLiteral("Close"));
    row->addWidget(m_meta, 1);
    row->addWidget(m_favorite);
    row->addWidget(save);
    row->addWidget(full);
    row->addWidget(site);
    row->addWidget(source);
    row->addWidget(close);
    root->addWidget(bar);

    connect(m_favorite, &QPushButton::clicked, this, &ViewerDialog::toggleFavorite);
    connect(save, &QPushButton::clicked, this, &ViewerDialog::saveCurrent);
    connect(full, &QPushButton::clicked, this, [this]() { loadCurrent(true); });
    connect(site, &QPushButton::clicked, this, &ViewerDialog::openSite);
    connect(source, &QPushButton::clicked, this, &ViewerDialog::openSource);
    connect(close, &QPushButton::clicked, this, &QDialog::reject);
    connect(m_tags, &QListWidget::itemClicked, this, [this](QListWidgetItem *item) {
        if (item)
            emit tagClicked(item->data(Qt::UserRole).toString());
    });
    connect(&FavoriteStore::instance(), &FavoriteStore::changed, this, [this]() {
        if (isVisible())
            refreshChrome();
    });
    new QShortcut(QKeySequence(Qt::Key_Escape), this, SLOT(reject()));
    new QShortcut(QKeySequence(Qt::Key_F), this, [this]() { toggleFavorite(); });
    new QShortcut(QKeySequence(QKeySequence::Save), this, [this]() { saveCurrent(); });
}

void ViewerDialog::showPosts(const QVector<BooruPost> &posts, int index) {
    m_posts = posts;
    m_index = qBound(0, index, qMax(posts.size() - 1, 0));
    m_scale = 1.0;
    show();
    raise();
    activateWindow();
    loadCurrent(GallerySettings::instance().loadFullQuality());
}

void ViewerDialog::appendPosts(const QVector<BooruPost> &posts) {
    m_posts += posts;
    refreshChrome();
}

void ViewerDialog::refreshChrome() {
    if (m_posts.isEmpty())
        return;
    const BooruPost &post = m_posts[m_index];
    m_meta->setText(QStringLiteral("%1  #%2  %3×%4  %5 / %6")
                        .arg(post.serverId)
                        .arg(post.id)
                        .arg(post.width)
                        .arg(post.height)
                        .arg(m_index + 1)
                        .arg(m_posts.size()));
    m_favorite->setText(FavoriteStore::instance().contains(post.globalId())
                            ? QStringLiteral("Unfavorite")
                            : QStringLiteral("Favorite"));
    m_tags->clear();
    QVector<BooruTag> tags;
    for (const QString &name : post.tags) {
        BooruTag tag;
        tag.name = name;
        tag.type = TagIndexStore::instance().typeFor(name);
        tags.append(tag);
    }
    const TagType order[] = {TagType::Copyright, TagType::Character, TagType::Artist, TagType::General,
                             TagType::Meta};
    for (TagType type : order) {
        bool header = false;
        for (const BooruTag &tag : tags) {
            if (tag.type != type)
                continue;
            if (!header) {
                auto *group = new QListWidgetItem(tagTypeTitle(type));
                group->setFlags(Qt::NoItemFlags);
                group->setForeground(tagTypeColor(type));
                m_tags->addItem(group);
                header = true;
            }
            auto *item = new QListWidgetItem(tag.name);
            item->setData(Qt::UserRole, tag.name);
            item->setForeground(tagTypeColor(type));
            m_tags->addItem(item);
        }
    }
    TagIndexStore::instance().resolve(post.tags, ServerStore::instance().enabledServers());
}

void ViewerDialog::loadCurrent(bool preferOriginal) {
    if (m_posts.isEmpty())
        return;
    const BooruPost &post = m_posts[m_index];
    const bool wantOriginal = preferOriginal || GallerySettings::instance().loadFullQuality();
    const QUrl url = wantOriginal && !post.fileUrl.isEmpty() ? post.fileUrl : post.viewerUrl();
    refreshChrome();
    emit currentChanged(m_index);
    if (m_index >= m_posts.size() - 8)
        emit nearEnd();
    m_image->setText(QStringLiteral("Loading…"));
    m_progress->setValue(0);
    m_progress->show();
    const int generation = ++m_generation;
    HttpClient::instance().get(
        url, {},
        [this, generation](QByteArray data, QString error) {
            if (generation != m_generation)
                return;
            m_progress->hide();
            if (!error.isEmpty() || !m_pixmap.loadFromData(data)) {
                m_image->setText(error.isEmpty() ? QStringLiteral("Image unavailable") : error);
                return;
            }
            applyPixmap();
        },
        [this, generation](qint64 received, qint64 total) {
            if (generation != m_generation || total <= 0)
                return;
            m_progress->setValue(int(received * 100 / total));
        },
        !wantOriginal);
}

void ViewerDialog::applyPixmap() {
    if (m_pixmap.isNull())
        return;
    const QSize box = m_scroll->viewport()->size();
    QSize fitted = m_pixmap.size();
    fitted.scale(box, Qt::KeepAspectRatio);
    const QSize shown = fitted * m_scale;
    m_image->setPixmap(m_pixmap.scaled(shown, Qt::KeepAspectRatio, Qt::SmoothTransformation));
}

void ViewerDialog::moveBy(int delta) {
    if (m_posts.isEmpty())
        return;
    m_index = qBound(0, m_index + delta, m_posts.size() - 1);
    m_scale = 1.0;
    loadCurrent(false);
}

void ViewerDialog::toggleFavorite() {
    if (m_posts.isEmpty())
        return;
    FavoriteStore::instance().toggle(m_posts[m_index]);
}

void ViewerDialog::saveCurrent() {
    if (m_posts.isEmpty())
        return;
    const BooruPost &post = m_posts[m_index];
    QString ext = post.fileExt;
    if (ext.isEmpty())
        ext = post.fileUrl.path().section(QLatin1Char('.'), -1);
    if (ext.isEmpty())
        ext = QStringLiteral("jpg");
    const QUrl url = post.fileUrl.isEmpty() ? post.viewerUrl() : post.fileUrl;
    const QString suggested = QStringLiteral("%1_%2.%3").arg(post.serverId, QString::number(post.id), ext);
    const QString path = QFileDialog::getSaveFileName(this, QStringLiteral("Save file"), suggested);
    if (path.isEmpty())
        return;
    HttpClient::instance().get(url, {}, [this, path](QByteArray data, QString error) {
        if (!error.isEmpty() || data.isEmpty()) {
            QMessageBox::warning(this, QStringLiteral("Save"),
                                 error.isEmpty() ? QStringLiteral("Download failed.") : error);
            return;
        }
        QFile file(path);
        if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size()) {
            QMessageBox::warning(this, QStringLiteral("Save"), QStringLiteral("Couldn't write the file."));
            return;
        }
    });
}

void ViewerDialog::openSite() {
    if (m_posts.isEmpty())
        return;
    const BooruPost &post = m_posts[m_index];
    const BooruServer server = ServerStore::instance().serverFor(post.serverId);
    QDesktopServices::openUrl(postPageUrl(post, server.flavor));
}

void ViewerDialog::openSource() {
    if (m_posts.isEmpty())
        return;
    const QUrl source = m_posts[m_index].sourceUrl;
    if (source.isEmpty())
        QMessageBox::information(this, QStringLiteral("Source"), QStringLiteral("No source URL on this post."));
    else
        QDesktopServices::openUrl(source);
}

void ViewerDialog::keyPressEvent(QKeyEvent *event) {
    if (event->key() == Qt::Key_Left)
        moveBy(-1);
    else if (event->key() == Qt::Key_Right)
        moveBy(1);
    else
        QDialog::keyPressEvent(event);
}

void ViewerDialog::wheelEvent(QWheelEvent *event) {
    if (event->modifiers() & Qt::ControlModifier) {
        m_scale = qBound(1.0, m_scale + (event->angleDelta().y() > 0 ? 0.15 : -0.15), 5.0);
        applyPixmap();
        event->accept();
        return;
    }
    QDialog::wheelEvent(event);
}

void ViewerDialog::resizeEvent(QResizeEvent *event) {
    QDialog::resizeEvent(event);
    applyPixmap();
}
