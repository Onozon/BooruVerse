#pragma once

#include "core/Models.h"

#include <QWidget>

class QLabel;
class QLineEdit;
class QListWidget;

class PoolListWidget : public QWidget {
    Q_OBJECT
public:
    explicit PoolListWidget(QWidget *parent = nullptr);

    QString query() const;
    void setEmptyHint(const QString &text);
    void setPools(const QVector<BooruPool> &pools);
    void appendPools(const QVector<BooruPool> &pools);
    void clear();

signals:
    void poolActivated(const BooruPool &pool);
    void querySubmitted(const QString &query);
    void nearBottom();

private:
    void addRow(const BooruPool &pool);

    QLineEdit *m_query = nullptr;
    QListWidget *m_list = nullptr;
    QLabel *m_empty = nullptr;
    QVector<BooruPool> m_pools;
};
