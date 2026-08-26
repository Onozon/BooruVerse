#include "ui/TagSidebar.h"

#include "core/PersonalFeedStore.h"
#include "core/SavedTagSetStore.h"
#include "core/TagIndexStore.h"

#include <QCheckBox>
#include <QCompleter>
#include <QDialog>
#include <QDialogButtonBox>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QMenu>
#include <QMessageBox>
#include <QPushButton>
#include <QScrollArea>
#include <QStringListModel>
#include <QVBoxLayout>

static QString tagLabel(const BooruTag &tag) {
    if (tag.postCount <= 0)
        return tag.name;
    return QStringLiteral("%1  ·  %2").arg(tag.name).arg(tag.postCount);
}

TagSidebar::TagSidebar(QWidget *parent)
    : QWidget(parent) {
    setMinimumWidth(220);
    auto *root = new QVBoxLayout(this);
    root->setContentsMargins(12, 12, 12, 12);
    root->setSpacing(8);

    auto *selectedRow = new QHBoxLayout;
    auto *selectedTitle = new QLabel(QStringLiteral("Selected"));
    selectedTitle->setStyleSheet(QStringLiteral("font-weight:600;"));
    auto *clear = new QPushButton(QStringLiteral("Clear"));
    selectedRow->addWidget(selectedTitle, 1);
    selectedRow->addWidget(clear);
    root->addLayout(selectedRow);

    m_chips = new QWidget;
    m_chipLayout = new QVBoxLayout(m_chips);
    m_chipLayout->setContentsMargins(0, 0, 0, 0);
    m_chipLayout->setSpacing(6);
    auto *chipScroll = new QScrollArea;
    chipScroll->setWidget(m_chips);
    chipScroll->setWidgetResizable(true);
    chipScroll->setFrameShape(QFrame::NoFrame);
    chipScroll->setMaximumHeight(160);
    root->addWidget(chipScroll);

    auto *inputRow = new QHBoxLayout;
    m_input = new QLineEdit;
    m_input->setPlaceholderText(QStringLiteral("Add tag…"));
    m_input->setClearButtonEnabled(true);
    auto *add = new QPushButton(QStringLiteral("Add"));
    inputRow->addWidget(m_input, 1);
    inputRow->addWidget(add);
    root->addLayout(inputRow);

    m_completionModel = new QStringListModel(this);
    m_completer = new QCompleter(m_completionModel, this);
    m_completer->setCaseSensitivity(Qt::CaseInsensitive);
    m_completer->setCompletionMode(QCompleter::UnfilteredPopupCompletion);
    m_completer->setFilterMode(Qt::MatchContains);
    m_input->setCompleter(m_completer);

    m_suggestions = new QListWidget;
    m_suggestions->setAlternatingRowColors(true);
    m_suggestions->setMaximumHeight(180);
    m_suggestions->hide();
    root->addWidget(m_suggestions);

    auto *savedHeader = new QHBoxLayout;
    auto *savedTitle = new QLabel(QStringLiteral("Saved sets"));
    savedTitle->setStyleSheet(QStringLiteral("font-weight:600;"));
    m_save = new QPushButton(QStringLiteral("Save"));
    savedHeader->addWidget(savedTitle, 1);
    savedHeader->addWidget(m_save);
    root->addLayout(savedHeader);

    m_saved = new QListWidget;
    m_saved->setAlternatingRowColors(true);
    m_saved->setMaximumHeight(140);
    m_saved->setContextMenuPolicy(Qt::CustomContextMenu);
    root->addWidget(m_saved);

    m_pageHeader = new QLabel(QStringLiteral("Tags on this page"));
    m_pageHeader->setStyleSheet(QStringLiteral("font-weight:600;"));
    root->addWidget(m_pageHeader);

    m_pageList = new QListWidget;
    m_pageList->setAlternatingRowColors(true);
    root->addWidget(m_pageList, 1);

    connect(clear, &QPushButton::clicked, this, &TagSidebar::clearTags);
    connect(m_input, &QLineEdit::returnPressed, this, &TagSidebar::commitInput);
    connect(add, &QPushButton::clicked, this, &TagSidebar::commitInput);
    connect(m_input, &QLineEdit::textEdited, this, [this](const QString &text) {
        refillPageList();
        emit fragmentChanged(text.trimmed());
    });
    connect(m_completer, QOverload<const QString &>::of(&QCompleter::activated), this,
            [this](const QString &name) { addTag(name); });
    connect(m_suggestions, &QListWidget::itemClicked, this, [this](QListWidgetItem *item) {
        if (item)
            addTag(item->data(Qt::UserRole).toString());
    });
    connect(m_pageList, &QListWidget::itemClicked, this, [this](QListWidgetItem *item) {
        if (item)
            addTag(item->data(Qt::UserRole).toString());
    });
    connect(m_save, &QPushButton::clicked, this, &TagSidebar::saveCurrentSet);
    connect(m_saved, &QListWidget::itemActivated, this, [this](QListWidgetItem *) { applySavedItem(); });
    connect(m_saved, &QListWidget::itemChanged, this, [this](QListWidgetItem *item) {
        if (!item)
            return;
        PersonalFeedStore::instance().setEnabled(item->data(Qt::UserRole).toString(),
                                                 item->checkState() == Qt::Checked);
    });
    connect(m_saved, &QWidget::customContextMenuRequested, this, [this](const QPoint &pos) {
        if (!m_saved->itemAt(pos))
            return;
        QMenu menu(this);
        menu.addAction(QStringLiteral("Load"), this, &TagSidebar::applySavedItem);
        menu.addAction(QStringLiteral("Delete"), this, &TagSidebar::deleteSavedItem);
        menu.exec(m_saved->mapToGlobal(pos));
    });
    connect(&SavedTagSetStore::instance(), &SavedTagSetStore::changed, this, &TagSidebar::reloadSavedSets);
    connect(&PersonalFeedStore::instance(), &PersonalFeedStore::changed, this, &TagSidebar::reloadSavedSets);
    connect(&TagIndexStore::instance(), &TagIndexStore::changed, this, &TagSidebar::refillPageList);
    m_pageList->setDragEnabled(true);
    m_suggestions->setDragEnabled(true);
    setAcceptDrops(true);

    rebuildChips();
    reloadSavedSets();
}

QString TagSidebar::joined() const {
    return m_tags.join(QLatin1Char(' '));
}

QString TagSidebar::fragment() const {
    return m_input->text().trimmed();
}

void TagSidebar::setTags(const QStringList &tags) {
    m_tags.clear();
    for (const QString &tag : tags) {
        const QString normalized = tag.trimmed().toLower();
        if (!normalized.isEmpty() && !m_tags.contains(normalized))
            m_tags.append(normalized);
    }
    m_input->clear();
    m_suggestions->clear();
    m_suggestions->hide();
    m_completionModel->setStringList({});
    rebuildChips();
    refillPageList();
    emit tagsChanged();
}

void TagSidebar::clearTags() {
    if (m_tags.isEmpty())
        return;
    m_tags.clear();
    rebuildChips();
    refillPageList();
    emit tagsChanged();
}

void TagSidebar::addTag(const QString &tag) {
    const QString normalized = tag.trimmed().toLower();
    if (normalized.isEmpty() || m_tags.contains(normalized)) {
        m_input->clear();
        return;
    }
    m_tags.append(normalized);
    m_input->clear();
    m_suggestions->clear();
    m_suggestions->hide();
    m_completionModel->setStringList({});
    rebuildChips();
    refillPageList();
    emit tagsChanged();
}

void TagSidebar::setPageTags(const QVector<BooruTag> &tags) {
    m_pageTags = tags;
    refillPageList();
}

void TagSidebar::setSuggestions(const QVector<BooruTag> &tags) {
    fillTagList(m_suggestions, tags);
    m_suggestions->setVisible(!tags.isEmpty());

    QStringList names;
    for (const BooruTag &tag : tags)
        names.append(tag.name);
    m_completionModel->setStringList(names);
    if (m_input->hasFocus() && !names.isEmpty())
        m_completer->complete();
}

void TagSidebar::rebuildChips() {
    QLayoutItem *item = nullptr;
    while ((item = m_chipLayout->takeAt(0))) {
        delete item->widget();
        delete item;
    }
    if (m_tags.isEmpty()) {
        auto *empty = new QLabel(QStringLiteral("No tags selected"));
        empty->setStyleSheet(QStringLiteral("color:#8e8e93;"));
        m_chipLayout->addWidget(empty);
        return;
    }
    for (const QString &tag : m_tags) {
        auto *row = new QWidget;
        auto *box = new QHBoxLayout(row);
        box->setContentsMargins(8, 4, 4, 4);
        box->setSpacing(6);
        auto *label = new QLabel(tag);
        auto *remove = new QPushButton(QStringLiteral("×"));
        remove->setFixedSize(22, 22);
        remove->setFlat(true);
        box->addWidget(label, 1);
        box->addWidget(remove);
        row->setStyleSheet(QStringLiteral("border:1px solid #c7c7cc; border-radius:6px;"));
        m_chipLayout->addWidget(row);
        connect(remove, &QPushButton::clicked, this, [this, tag]() {
            m_tags.removeAll(tag);
            rebuildChips();
            refillPageList();
            emit tagsChanged();
        });
    }
}

void TagSidebar::commitInput() {
    addTag(m_input->text());
}

void TagSidebar::refillPageList() {
    const QString fragment = m_input->text().trimmed();
    QVector<BooruTag> visible;
    for (const BooruTag &tag : m_pageTags) {
        if (m_tags.contains(tag.name, Qt::CaseInsensitive))
            continue;
        if (!fragment.isEmpty() && !tag.name.contains(fragment, Qt::CaseInsensitive))
            continue;
        visible.append(tag);
    }
    fillTagList(m_pageList, visible);
    m_pageHeader->setText(visible.isEmpty()
                              ? QStringLiteral("Tags on this page")
                              : QStringLiteral("Tags on this page  ·  %1").arg(visible.size()));
}

void TagSidebar::fillTagList(QListWidget *list, const QVector<BooruTag> &tags) {
    list->clear();
    QVector<BooruTag> typed = tags;
    TagIndexStore::instance().applyTo(typed);
    const TagType order[] = {TagType::Copyright, TagType::Character, TagType::Artist, TagType::General,
                             TagType::Meta};
    for (TagType type : order) {
        bool header = false;
        for (const BooruTag &tag : typed) {
            if (tag.type != type)
                continue;
            if (!header) {
                auto *group = new QListWidgetItem(tagTypeTitle(type));
                group->setFlags(Qt::NoItemFlags);
                group->setForeground(tagTypeColor(type));
                list->addItem(group);
                header = true;
            }
            auto *item = new QListWidgetItem(tagLabel(tag));
            item->setData(Qt::UserRole, tag.name);
            item->setForeground(tagTypeColor(type));
            list->addItem(item);
        }
    }
}

void TagSidebar::reloadSavedSets() {
    m_saved->blockSignals(true);
    m_saved->clear();
    for (const SavedTagSet &set : SavedTagSetStore::instance().sets()) {
        auto *item = new QListWidgetItem(QStringLiteral("%1  ·  %2").arg(set.name, set.joined()));
        item->setData(Qt::UserRole, set.id);
        item->setFlags(item->flags() | Qt::ItemIsUserCheckable);
        item->setCheckState(PersonalFeedStore::instance().contains(set.id) ? Qt::Checked : Qt::Unchecked);
        item->setToolTip(QStringLiteral("Double-click to load. Check to include in Personal feed."));
        m_saved->addItem(item);
    }
    m_saved->blockSignals(false);
}

void TagSidebar::saveCurrentSet() {
    if (m_tags.isEmpty()) {
        QMessageBox::information(this, QStringLiteral("Save set"),
                                 QStringLiteral("Add at least one tag first."));
        return;
    }
    QDialog dialog(this);
    dialog.setWindowTitle(QStringLiteral("Save tag set"));
    auto *root = new QVBoxLayout(&dialog);
    auto *name = new QLineEdit;
    name->setPlaceholderText(QStringLiteral("Name"));
    name->setText(m_tags.join(QLatin1Char(' ')));
    auto *personal = new QCheckBox(QStringLiteral("Also add to Personal feed"));
    root->addWidget(name);
    root->addWidget(personal);
    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Ok | QDialogButtonBox::Cancel);
    root->addWidget(buttons);
    connect(buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject);
    if (dialog.exec() != QDialog::Accepted)
        return;
    SavedTagSetStore::instance().save(name->text(), m_tags, personal->isChecked());
}

void TagSidebar::applySavedItem() {
    QListWidgetItem *item = m_saved->currentItem();
    if (!item)
        return;
    const SavedTagSet set = SavedTagSetStore::instance().setFor(item->data(Qt::UserRole).toString());
    if (!set.tags.isEmpty())
        setTags(set.tags);
}

void TagSidebar::deleteSavedItem() {
    QListWidgetItem *item = m_saved->currentItem();
    if (!item)
        return;
    SavedTagSetStore::instance().remove(item->data(Qt::UserRole).toString());
}
