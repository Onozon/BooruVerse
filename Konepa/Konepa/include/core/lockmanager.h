#ifndef LOCKMANAGER_H
#define LOCKMANAGER_H

#include <QMutex>
#include <QRecursiveMutex>
#include <QReadWriteLock>
#include <QHash>
#include <QString>
#include <QMutexLocker>
#include <QReadLocker>
#include <QWriteLocker>
#include <memory>

/**
 * @brief Централизованный менеджер блокировок для синхронизации потоков
 * 
 * Управляет всеми блокировками в приложении, обеспечивая:
 * - Единую точку доступа к блокировкам
 * - Автоматическое управление жизненным циклом блокировок
 * - Защиту от взаимоблокировок
 * - Логирование доступа к блокировкам (в debug режиме)
 */
class LockManager
{
public:
    static LockManager& instance();
    
    // Блокировки для различных компонентов
    enum LockType {
        // Основные данные
        ArtistsList,           // Список всех авторов
        PostsList,             // Список постов
        CurrentArtist,         // Текущий выбранный автор
        CurrentPost,           // Текущий выбранный пост
        
        // Кэш
        CacheManager,          // Менеджер кэша
        PreviewCache,          // Кэш превью
        ThumbnailCache,        // Кэш миниатюр
        MetadataCache,         // Кэш метаданных
        
        // Сетевые операции
        NetworkRequests,       // Сетевые запросы
        DownloadQueue,         // Очередь загрузок
        ThumbnailQueue,        // Очередь миниатюр
        
        // UI состояние
        UIState,               // Состояние интерфейса
        SectionState,          // Состояние секций
        History,               // История просмотров
        
        // Парсер
        Parser,                // Парсер API
        
        // Медиа
        MediaViewer,           // Просмотрщик медиа
        PostViewer,            // Просмотрщик постов
        
        // Счетчики и индексы
        Counters,              // Различные счетчики
        
        LockTypeCount          // Количество типов блокировок
    };
    
    /**
     * @brief Получить мьютекс для чтения/записи
     * @param type Тип блокировки
     * @return Умный указатель на рекурсивный мьютекс
     */
    QRecursiveMutex* getMutex(LockType type);
    
    /**
     * @brief Получить read-write блокировку
     * @param type Тип блокировки
     * @return Умный указатель на read-write блокировку
     */
    QReadWriteLock* getReadWriteLock(LockType type);
    
    /**
     * @brief Блокировка для чтения (RAII)
     */
    class ReadLock {
    public:
        ReadLock(LockType type);
        ~ReadLock();
        void unlock();
        void relock();
        
    private:
        LockType m_type;
        QReadLocker* m_locker;
        bool m_locked;
    };
    
    /**
     * @brief Блокировка для записи (RAII)
     */
    class WriteLock {
    public:
        WriteLock(LockType type);
        ~WriteLock();
        void unlock();
        void relock();
        
    private:
        LockType m_type;
        QWriteLocker* m_locker;
        bool m_locked;
    };
    
    /**
     * @brief Мьютекс блокировка (RAII)
     */
    class MutexLock {
    public:
        MutexLock(LockType type);
        ~MutexLock();
        void unlock();
        void relock();
        
    private:
        LockType m_type;
        QMutexLocker<QRecursiveMutex>* m_locker;
        bool m_locked;
    };
    
    /**
     * @brief Проверить, заблокирован ли мьютекс (только для отладки)
     */
    bool isLocked(LockType type) const;
    
    /**
     * @brief Очистить все блокировки (использовать с осторожностью!)
     */
    void clear();

private:
    LockManager();
    ~LockManager();
    LockManager(const LockManager&) = delete;
    LockManager& operator=(const LockManager&) = delete;
    
    void initializeLocks();
    
    QHash<LockType, QRecursiveMutex*> m_mutexes;
    QHash<LockType, QReadWriteLock*> m_readWriteLocks;
    
    // Для отслеживания блокировок в debug режиме
    mutable QHash<LockType, int> m_lockCounters;
    mutable QRecursiveMutex m_counterMutex;
    
    friend class ReadLock;
    friend class WriteLock;
    friend class MutexLock;
};

// Макросы для удобства использования
// Используем уникальные имена переменных для избежания конфликтов
#define LOCK_READ(type) LockManager::ReadLock _lock_##type(LockManager::type)
#define LOCK_WRITE(type) LockManager::WriteLock _lock_##type(LockManager::type)
#define LOCK_MUTEX(type) LockManager::MutexLock _lock_##type(LockManager::type)

#endif // LOCKMANAGER_H

