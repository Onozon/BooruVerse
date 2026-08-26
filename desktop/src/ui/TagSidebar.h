#pragma once

#include "core/Models.h"

#include <QWidget>

class QCompleter;
class QLabel;
class QLineEdit;
class QListWidget;
class QPushButton;
class QStringListModel;
class QVBoxLayout;

class TagSidebar : public QWidget {
    Q_OBJECT
public:
    explicit TagSidebar(QWidget *parent = nullptr);

    QStringList tags() const { return m_tags; }
    QString joined() const;
    QString fragment() const;
    void setTags(const QStringList &tags);
    void addTag(const QString &tag);
    void setPageTags(const QVector<BooruTag> &tags);
    void setSuggestions(const QVector<BooruTag> &tags);
    void clearTags();

signals:
    void tagsChanged();
    void fragmentChanged(const QString &fragment);

private:
    void rebuildChips();
    void commitInput();
    void refillPageList();
    void fillTagList(QListWidget *list, const QVector<BooruTag> &tags);
    void reloadSavedSets();
    void saveCurrentSet();
    void applySavedItem();
    void deleteSavedItem();

    QStringList m_tags;
    QVector<BooruTag> m_pageTags;
    QWidget *m_chips = nullptr;
    QVBoxLayout *m_chipLayout = nullptr;
    QLineEdit *m_input = nullptr;
    QListWidget *m_suggestions = nullptr;
    QListWidget *m_saved = nullptr;
    QListWidget *m_pageList = nullptr;
    QLabel *m_pageHeader = nullptr;
    QPushButton *m_save = nullptr;
    QCompleter *m_completer = nullptr;
    QStringListModel *m_completionModel = nullptr;
};
