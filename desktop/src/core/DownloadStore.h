#pragma once

#include "core/Models.h"

#include <QAbstractListModel>
#include <QHash>
#include <QSet>
#include <QTimer>

class DownloadStore : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ rowCount NOTIFY countChanged)
    Q_PROPERTY(bool hasFailed READ hasFailed NOTIFY statusChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY statusChanged)
    Q_PROPERTY(bool allSucceeded READ allSucceeded NOTIFY statusChanged)
    Q_PROPERTY(bool visible READ visible NOTIFY statusChanged)
public:
    enum Status { Queued, Running, Failed, Done };
    Q_ENUM(Status)

    enum Role {
        NameRole = Qt::UserRole + 1,
        PreviewRole,
        StatusRole,
        ProgressRole,
        ErrorRole,
        PathRole
    };

    static DownloadStore &instance();

    int rowCount(const QModelIndex &parent = {}) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    bool hasFailed() const;
    bool busy() const { return m_running > 0; }
    bool allSucceeded() const { return m_allSucceeded; }
    bool visible() const;

    void enqueue(const QVector<BooruPost> &posts, const QString &destDir);
    Q_INVOKABLE void retryFailed();
    Q_INVOKABLE void openItem(int index);

signals:
    void countChanged();
    void statusChanged();

private:
    struct Job {
        BooruPost post;
        QString destDir;
        QString destPath;
        Status status = Queued;
        double progress = 0;
        QString error;
    };

    explicit DownloadStore(QObject *parent = nullptr);
    void pump();
    void startJob(int index);
    QString fileNameFor(const BooruPost &post) const;
    void refreshVisible();

    QVector<Job> m_jobs;
    QSet<QString> m_activeIds;
    int m_running = 0;
    bool m_allSucceeded = false;
    QTimer m_hideTimer;
};
