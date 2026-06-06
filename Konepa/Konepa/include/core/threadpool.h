#ifndef THREADPOOL_H
#define THREADPOOL_H

#include <QObject>
#include <QRunnable>
#include <QThreadPool>
#include <QFuture>
#include <QFutureWatcher>
#include <QtConcurrent>
#include <functional>
#include <memory>
#include <type_traits>

/**
 * @brief Пул потоков для выполнения задач в фоновых потоках
 * 
 * Обеспечивает:
 * - Централизованное управление потоками
 * - Автоматическое масштабирование количества потоков
 * - Приоритеты задач
 * - Отслеживание выполнения задач
 */
class ThreadPool : public QObject
{
    Q_OBJECT

public:
    enum Priority {
        LowPriority = 0,
        NormalPriority = 1,
        HighPriority = 2
    };
    
    static ThreadPool& instance();
    
    /**
     * @brief Выполнить задачу в фоновом потоке
     * @param task Функция для выполнения
     * @param priority Приоритет задачи
     * @return Уникальный ID задачи
     */
    template<typename Func>
    int runTask(Func task, Priority priority = NormalPriority);
    
    /**
     * @brief Выполнить задачу с результатом
     * @param task Функция для выполнения
     * @param priority Приоритет задачи
     * @return QFuture для получения результата
     */
    template<typename Func>
    QFuture<typename std::invoke_result<Func>::type> runTaskWithResult(Func task, Priority priority = NormalPriority);
    
    /**
     * @brief Отменить задачу
     * @param taskId ID задачи
     */
    void cancelTask(int taskId);
    
    /**
     * @brief Установить максимальное количество потоков
     */
    void setMaxThreadCount(int count);
    
    /**
     * @brief Получить максимальное количество потоков
     */
    int maxThreadCount() const;
    
    /**
     * @brief Получить количество активных задач
     */
    int activeTaskCount() const;
    
    /**
     * @brief Ожидать завершения всех задач
     */
    void waitForDone(int msecs = -1);
    
    /**
     * @brief Очистить очередь задач
     */
    void clear();

signals:
    void taskStarted(int taskId);
    void taskFinished(int taskId);
    void taskFailed(int taskId, const QString& error);

private:
    explicit ThreadPool(QObject* parent = nullptr);
    ~ThreadPool();
    ThreadPool(const ThreadPool&) = delete;
    ThreadPool& operator=(const ThreadPool&) = delete;
    
    class TaskRunnable : public QRunnable
    {
    public:
        TaskRunnable(int taskId, std::function<void()> task, ThreadPool* pool);
        void run() override;
        
    private:
        int m_taskId;
        std::function<void()> m_task;
        ThreadPool* m_pool;
    };
    
    QThreadPool* m_threadPool;
    int m_nextTaskId;
    QHash<int, QFutureWatcher<void>*> m_taskWatchers;
};

// Реализация шаблонных методов
template<typename Func>
int ThreadPool::runTask(Func task, Priority priority)
{
    int taskId = m_nextTaskId++;
    
    TaskRunnable* runnable = new TaskRunnable(taskId, task, this);
    runnable->setAutoDelete(true);
    
    // Устанавливаем приоритет
    int qPriority = QThread::NormalPriority;
    switch (priority) {
        case LowPriority:
            qPriority = QThread::LowPriority;
            break;
        case HighPriority:
            qPriority = QThread::HighPriority;
            break;
        default:
            qPriority = QThread::NormalPriority;
            break;
    }
    
    emit taskStarted(taskId);
    m_threadPool->start(runnable, qPriority);
    
    return taskId;
}

template<typename Func>
QFuture<typename std::invoke_result<Func>::type> ThreadPool::runTaskWithResult(Func task, Priority priority)
{
    // Используем QtConcurrent для задач с результатом
    return QtConcurrent::run(m_threadPool, task);
}

#endif // THREADPOOL_H

