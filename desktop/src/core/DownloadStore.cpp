#include "core/DownloadStore.h"

#include "core/HttpClient.h"

#include <QDesktopServices>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>

DownloadStore &DownloadStore::instance() {
    static DownloadStore store;
    return store;
}

DownloadStore::DownloadStore(QObject *parent)
    : QAbstractListModel(parent) {
    m_hideTimer.setSingleShot(true);
    m_hideTimer.setInterval(3000);
    connect(&m_hideTimer, &QTimer::timeout, this, [this]() {
        if (!busy() && !hasFailed()) {
            beginResetModel();
            m_jobs.clear();
            m_activeIds.clear();
            m_allSucceeded = false;
            endResetModel();
            emit countChanged();
            emit statusChanged();
        }
    });
}

int DownloadStore::rowCount(const QModelIndex &parent) const {
    return parent.isValid() ? 0 : m_jobs.size();
}

QVariant DownloadStore::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || index.row() >= m_jobs.size())
        return {};
    const Job &job = m_jobs[index.row()];
    switch (role) {
    case NameRole:
        return QFileInfo(job.destPath).fileName();
    case PreviewRole:
        return job.post.previewUrl.toString();
    case StatusRole:
        return int(job.status);
    case ProgressRole:
        return job.progress;
    case ErrorRole:
        return job.error;
    case PathRole:
        return job.destPath;
    default:
        return {};
    }
}

QHash<int, QByteArray> DownloadStore::roleNames() const {
    return {{NameRole, "fileName"}, {PreviewRole, "previewUrl"}, {StatusRole, "status"},
            {ProgressRole, "progress"}, {ErrorRole, "errorText"}, {PathRole, "destPath"}};
}

bool DownloadStore::hasFailed() const {
    for (const Job &job : m_jobs) {
        if (job.status == Failed)
            return true;
    }
    return false;
}

bool DownloadStore::visible() const {
    return !m_jobs.isEmpty() && (busy() || hasFailed() || m_allSucceeded);
}

void DownloadStore::enqueue(const QVector<BooruPost> &posts, const QString &destDir) {
    QString dir = destDir.trimmed();
    if (dir.startsWith(QLatin1String("file:")))
        dir = QUrl(dir).toLocalFile();
    if (posts.isEmpty() || dir.isEmpty())
        return;
    m_hideTimer.stop();
    m_allSucceeded = false;
    QDir().mkpath(dir);
    QVector<Job> added;
    for (const BooruPost &post : posts) {
        const QString id = post.globalId();
        if (m_activeIds.contains(id))
            continue;
        Job job;
        job.post = post;
        job.destDir = dir;
        job.destPath = QDir(dir).filePath(fileNameFor(post));
        job.status = Queued;
        added.append(job);
        m_activeIds.insert(id);
    }
    if (added.isEmpty()) {
        emit statusChanged();
        return;
    }
    const int start = m_jobs.size();
    beginInsertRows({}, start, start + added.size() - 1);
    m_jobs += added;
    endInsertRows();
    emit countChanged();
    emit statusChanged();
    pump();
}

void DownloadStore::retryFailed() {
    bool any = false;
    for (int i = 0; i < m_jobs.size(); ++i) {
        if (m_jobs[i].status != Failed)
            continue;
        m_jobs[i].status = Queued;
        m_jobs[i].progress = 0;
        m_jobs[i].error.clear();
        emit dataChanged(index(i), index(i));
        any = true;
    }
    if (!any)
        return;
    m_hideTimer.stop();
    m_allSucceeded = false;
    emit statusChanged();
    pump();
}

void DownloadStore::openItem(int row) {
    if (row < 0 || row >= m_jobs.size())
        return;
    if (m_jobs[row].status == Done)
        QDesktopServices::openUrl(QUrl::fromLocalFile(m_jobs[row].destPath));
}

void DownloadStore::pump() {
    while (m_running < 4) {
        int next = -1;
        for (int i = 0; i < m_jobs.size(); ++i) {
            if (m_jobs[i].status == Queued) {
                next = i;
                break;
            }
        }
        if (next < 0)
            break;
        startJob(next);
    }
    refreshVisible();
}

void DownloadStore::startJob(int row) {
    Job &job = m_jobs[row];
    job.status = Running;
    job.progress = 0;
    ++m_running;
    emit dataChanged(index(row), index(row));
    emit statusChanged();

    QUrl url = job.post.fileUrl.isEmpty() ? job.post.viewerUrl() : job.post.fileUrl;
    const QString path = job.destPath;
    HttpClient::instance().download(url, [this, row](QByteArray data, QString error) {
        if (row < 0 || row >= m_jobs.size())
            return;
        --m_running;
        Job &done = m_jobs[row];
        if (!error.isEmpty() || data.isEmpty()) {
            done.status = Failed;
            done.error = error.isEmpty() ? QStringLiteral("Empty response") : error;
            done.progress = 0;
        } else {
            QFile file(done.destPath);
            if (!file.open(QIODevice::WriteOnly) || file.write(data) != data.size()) {
                done.status = Failed;
                done.error = QStringLiteral("Couldn't write file");
            } else {
                done.status = Done;
                done.progress = 1;
                done.error.clear();
            }
        }
        emit dataChanged(index(row), index(row));
        emit statusChanged();
        pump();
    }, [this, row](qint64 received, qint64 total) {
        if (row < 0 || row >= m_jobs.size() || total <= 0)
            return;
        m_jobs[row].progress = double(received) / double(total);
        emit dataChanged(index(row), index(row), {ProgressRole});
    });
    Q_UNUSED(path);
}

QString DownloadStore::fileNameFor(const BooruPost &post) const {
    QString ext = post.fileExt;
    if (ext.isEmpty())
        ext = QStringLiteral("jpg");
    QString name = QStringLiteral("%1_%2.%3").arg(post.serverId, QString::number(post.id), ext);
    name.replace(QLatin1Char('/'), QLatin1Char('_'));
    return name;
}

void DownloadStore::refreshVisible() {
    if (m_running > 0 || hasFailed()) {
        m_allSucceeded = false;
        m_hideTimer.stop();
        emit statusChanged();
        return;
    }
    if (m_jobs.isEmpty()) {
        m_allSucceeded = false;
        emit statusChanged();
        return;
    }
    bool anyDone = false;
    for (const Job &job : m_jobs) {
        if (job.status != Done)
            return;
        anyDone = true;
    }
    if (!anyDone)
        return;
    m_allSucceeded = true;
    emit statusChanged();
    m_hideTimer.start();
}
