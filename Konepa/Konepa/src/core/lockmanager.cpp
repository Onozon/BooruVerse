#include "core/lockmanager.h"
#include <QDebug>
#include <QMutexLocker>

LockManager& LockManager::instance()
{
    static LockManager instance;
    return instance;
}

LockManager::LockManager()
{
    initializeLocks();
}

LockManager::~LockManager()
{
    clear();
}

void LockManager::initializeLocks()
{
    // Инициализируем все мьютексы
    for (int i = 0; i < LockTypeCount; ++i) {
        LockType type = static_cast<LockType>(i);
        m_mutexes[type] = new QRecursiveMutex(); // Рекурсивные мьютексы для безопасности
        m_readWriteLocks[type] = new QReadWriteLock();
        m_lockCounters[type] = 0;
    }
}

QRecursiveMutex* LockManager::getMutex(LockType type)
{
    if (type < 0 || type >= LockTypeCount) {
        qWarning() << "LockManager: Invalid lock type" << type;
        return nullptr;
    }
    return m_mutexes.value(type, nullptr);
}

QReadWriteLock* LockManager::getReadWriteLock(LockType type)
{
    if (type < 0 || type >= LockTypeCount) {
        qWarning() << "LockManager: Invalid lock type" << type;
        return nullptr;
    }
    return m_readWriteLocks.value(type, nullptr);
}

bool LockManager::isLocked(LockType type) const
{
    // Счетчики убраны, всегда возвращаем false
    Q_UNUSED(type);
    return false;
}

void LockManager::clear()
{
    // Очищаем все блокировки
    for (auto mutex : m_mutexes.values()) {
        if (mutex) {
            delete mutex;
        }
    }
    m_mutexes.clear();
    
    for (auto rwLock : m_readWriteLocks.values()) {
        if (rwLock) {
            delete rwLock;
        }
    }
    m_readWriteLocks.clear();
    
    m_lockCounters.clear();
}

// ReadLock implementation
LockManager::ReadLock::ReadLock(LockType type)
    : m_type(type)
    , m_locker(nullptr)
    , m_locked(true)
{
    LockManager& manager = LockManager::instance();
    QReadWriteLock* lock = manager.getReadWriteLock(type);
    if (lock) {
        m_locker = new QReadLocker(lock);
        // Счетчики убраны для упрощения и избежания рекурсивных вызовов
    }
}

LockManager::ReadLock::~ReadLock()
{
    unlock();
}

void LockManager::ReadLock::unlock()
{
    if (m_locked && m_locker) {
        delete m_locker;
        m_locker = nullptr;
        m_locked = false;
        // Счетчики убраны для упрощения
    }
}

void LockManager::ReadLock::relock()
{
    if (!m_locked) {
        LockManager& manager = LockManager::instance();
        QReadWriteLock* lock = manager.getReadWriteLock(m_type);
        if (lock) {
            m_locker = new QReadLocker(lock);
            m_locked = true;
            // Счетчики убраны для упрощения
        }
    }
}

// WriteLock implementation
LockManager::WriteLock::WriteLock(LockType type)
    : m_type(type)
    , m_locker(nullptr)
    , m_locked(true)
{
    LockManager& manager = LockManager::instance();
    QReadWriteLock* lock = manager.getReadWriteLock(type);
    if (lock) {
        m_locker = new QWriteLocker(lock);
        // Счетчики убраны для упрощения
    }
}

LockManager::WriteLock::~WriteLock()
{
    unlock();
}

void LockManager::WriteLock::unlock()
{
    if (m_locked && m_locker) {
        delete m_locker;
        m_locker = nullptr;
        m_locked = false;
        // Счетчики убраны для упрощения
    }
}

void LockManager::WriteLock::relock()
{
    if (!m_locked) {
        QReadWriteLock* lock = LockManager::instance().getReadWriteLock(m_type);
        if (lock) {
            m_locker = new QWriteLocker(lock);
            m_locked = true;
            
            // Обновляем счетчик
            QMutexLocker counterLocker(&LockManager::instance().m_counterMutex);
            LockManager::instance().m_lockCounters[m_type]++;
        }
    }
}

// MutexLock implementation
LockManager::MutexLock::MutexLock(LockType type)
    : m_type(type)
    , m_locker(nullptr)
    , m_locked(true)
{
    LockManager& manager = LockManager::instance();
    QRecursiveMutex* mutex = manager.getMutex(m_type);
    if (mutex) {
        m_locker = new QMutexLocker<QRecursiveMutex>(mutex);
        // Счетчики убраны для упрощения
    }
}

LockManager::MutexLock::~MutexLock()
{
    unlock();
}

void LockManager::MutexLock::unlock()
{
    if (m_locked && m_locker) {
        delete m_locker;
        m_locker = nullptr;
        m_locked = false;
        // Счетчики убраны для упрощения
    }
}

void LockManager::MutexLock::relock()
{
    if (!m_locked) {
        LockManager& manager = LockManager::instance();
        QRecursiveMutex* mutex = manager.getMutex(m_type);
        if (mutex) {
            m_locker = new QMutexLocker<QRecursiveMutex>(mutex);
            m_locked = true;
            // Счетчики убраны для упрощения
        }
    }
}

