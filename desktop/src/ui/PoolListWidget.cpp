#include "ui/PoolListWidget.h"

#include "core/ServerStore.h"

#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QScrollBar>
#include <QVBoxLayout>

PoolListWidget::PoolListWidget(QWidget *parent)
    : QWidget(parent) {
    setMinimumWidth(260);
    auto *root = new QVBoxLayout(this);
    root->setContentsMargins(12, 12, 12, 12);
    root->setSpacing(8);

    auto *title = new QLabel(QStringLiteral("Pools"));
    title->setStyleSheet(QStringLiteral("font-weight:600;"));
    root->addWidget(title);

    m_query = new QLineEdit;
    m_query->setPlaceholderText(QStringLiteral("Search pools"));
    m_query->setClearButtonEnabled(true);
    root->addWidget(m_query);

    m_empty = new QLabel(QStringLiteral("Enable yande.re or konachan.com in Settings."));
    m_empty->setWordWrap(true);
    m_empty->setStyleSheet(QStringLiteral("color:#8e8e93;"));
    root->addWidget(m_empty);

    m_list = new QListWidget;
    m_list->setWordWrap(true);
    root->addWidget(m_list, 1);

    connect(m_query, &QLineEdit::returnPressed, this, [this]() { emit querySubmitted(query()); });
    connect(m_list, &QListWidget::itemActivated, this, [this](QListWidgetItem *item) {
        const int index = m_list->row(item);
        if (index >= 0 && index < m_pools.size())
            emit poolActivated(m_pools[index]);
    });
    connect(m_list, &QListWidget::itemClicked, this, [this](QListWidgetItem *item) {
        const int index = m_list->row(item);
        if (index >= 0 && index < m_pools.size())
            emit poolActivated(m_pools[index]);
    });
    connect(m_list->verticalScrollBar(), &QScrollBar::valueChanged, this, [this](int value) {
        QScrollBar *bar = m_list->verticalScrollBar();
        if (bar->maximum() > 0 && value > bar->maximum() - 80)
            emit nearBottom();
    });
}

QString PoolListWidget::query() const {
    return m_query->text().trimmed();
}

void PoolListWidget::setEmptyHint(const QString &text) {
    m_empty->setText(text);
}

void PoolListWidget::setPools(const QVector<BooruPool> &pools) {
    m_pools = pools;
    m_list->clear();
    for (const BooruPool &pool : m_pools)
        addRow(pool);
    m_empty->setVisible(m_pools.isEmpty());
}

void PoolListWidget::appendPools(const QVector<BooruPool> &pools) {
    if (pools.isEmpty())
        return;
    m_pools += pools;
    for (const BooruPool &pool : pools)
        addRow(pool);
    m_empty->setVisible(m_pools.isEmpty());
}

void PoolListWidget::clear() {
    m_pools.clear();
    m_list->clear();
    m_empty->setVisible(true);
}

void PoolListWidget::addRow(const BooruPool &pool) {
    const QColor color = ServerStore::instance().colorFor(pool.serverId);
    const QString text = QStringLiteral("%1\n%2 · %3")
                             .arg(pool.displayName())
                             .arg(pool.postCount)
                             .arg(pool.serverId);
    auto *item = new QListWidgetItem(text);
    if (color.isValid())
        item->setForeground(color);
    m_list->addItem(item);
    m_empty->setVisible(false);
}
