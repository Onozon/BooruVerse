#include "core/threadpool.h"
#include <QtConcurrent>
#include <QDebug>
#include <QElapsedTimer>

ThreadPool& ThreadPool::instance()
{
    static ThreadPool instance;
    return instance;
}

ThreadPool::ThreadPool(QObject* parent)
    : QObject(parent)
    , m_threadPool(new QThreadPool(this))
    , m_nextTaskId(1)
{
    // Устанавливаем оптимальное количество потоков
    // Обычно это количество ядер процессора
    int idealThreadCount = QThread::idealThreadCount();
    m_threadPool->setMaxThreadCount(qMax(4, idealThreadCount * 2)); // Минимум 4 потока
    
    qDebug() << "ThreadPool initialized with" << m_threadPool->maxThreadCount() << "threads";
}

ThreadPool::~ThreadPool()
{
    waitForDone(5000); // Ждем 5 секунд для завершения задач
    clear();
}

void ThreadPool::setMaxThreadCount(int count)
{
    m_threadPool->setMaxThreadCount(qMax(1, count));
}

int ThreadPool::maxThreadCount() const
{
    return m_threadPool->maxThreadCount();
}

int ThreadPool::activeTaskCount() const
{
    return m_threadPool->activeThreadCount();
}

void ThreadPool::waitForDone(int msecs)
{
    if (msecs < 0) {
        m_threadPool->waitForDone();
    } else {
        // Ждем с таймаутом
        QElapsedTimer timer;
        timer.start();
        while (m_threadPool->activeThreadCount() > 0 && timer.elapsed() < msecs) {
            QThread::msleep(10);
        }
    }
}

void ThreadPool::clear()
{
    // Отменяем все задачи
    for (auto watcher : m_taskWatchers.values()) {
        if (watcher) {
            watcher->cancel();
            watcher->deleteLater();
        }
    }
    m_taskWatchers.clear();
}

void ThreadPool::cancelTask(int taskId)
{
    QFutureWatcher<void>* watcher = m_taskWatchers.value(taskId, nullptr);
    if (watcher) {
        watcher->cancel();
        m_taskWatchers.remove(taskId);
        watcher->deleteLater();
    }
}

// TaskRunnable implementation
ThreadPool::TaskRunnable::TaskRunnable(int taskId, std::function<void()> task, ThreadPool* pool)
    : m_taskId(taskId)
    , m_task(task)
    , m_pool(pool)
{
}

void ThreadPool::TaskRunnable::run()
{
    try {
        if (m_task) {
            m_task();
        }
        emit m_pool->taskFinished(m_taskId);
    } catch (const std::exception& e) {
        emit m_pool->taskFailed(m_taskId, QString::fromStdString(e.what()));
    } catch (...) {
        emit m_pool->taskFailed(m_taskId, "Unknown error");
    }
}

