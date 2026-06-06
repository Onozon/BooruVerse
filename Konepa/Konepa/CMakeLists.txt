cmake_minimum_required(VERSION 3.25)

project(Konepa VERSION 1.0 LANGUAGES CXX)

# Настройка Qt
find_package(Qt6 REQUIRED COMPONENTS Core Gui Quick Network Widgets Concurrent)

# Обязательно: инициализация проекта
qt_standard_project_setup()

# Устанавливаем политику Qt для QML модулей (подавляет предупреждение)
qt_policy(SET QTP0001 NEW)

# Устанавливаем C++ стандарт
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Явно устанавливаем текущую директорию источника
set(CMAKE_CURRENT_SOURCE_DIR "${CMAKE_CURRENT_SOURCE_DIR}")

# Включаем директории
include_directories(include)

# Создаём исполняемый файл
qt_add_executable(Konepa
    main.cpp
    
    # Models
    src/models/artist.cpp
    src/models/post.cpp
    
    # Parser (заголовочный файл нужен для MOC)
    include/parser/kemonoparser.h
    src/parser/kemonoparser.cpp
    
    # GUI (заголовочные файлы нужны для MOC)
    include/gui/mainwindow.h
    src/gui/mainwindow.cpp
    src/gui/mainwindow_sidebar.cpp
    include/gui/mediaviewer.h
    src/gui/mediaviewer.cpp
    include/gui/imageprocessor.h
    src/gui/imageprocessor.cpp
    include/gui/sectionstate.h
    include/gui/historymanager.h
    src/gui/historymanager.cpp
    include/gui/postviewer.h
    src/gui/postviewer.cpp
    
    # Cache
    include/cache/cachemanager.h
    src/cache/cachemanager.cpp
    
    # Core (Threading and Locks)
    include/core/lockmanager.h
    src/core/lockmanager.cpp
    include/core/threadpool.h
    src/core/threadpool.cpp
    include/core/mediadownloadmanager.h
    src/core/mediadownloadmanager.cpp
)

# Подключаем QML файлы как ресурсы (обход проблемы с пробелами в путях)
qt_add_resources(Konepa "qml"
    PREFIX "/"
    FILES
        Main.qml
)

# Находим zlib для распаковки gzip
find_package(ZLIB REQUIRED)

# Добавляем QtConcurrent для ThreadPool
find_package(Qt6 REQUIRED COMPONENTS Concurrent)

# Линкуем Qt модули и zlib
target_link_libraries(Konepa PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Quick
    Qt6::Network
    Qt6::Widgets
    Qt6::Concurrent
    ZLIB::ZLIB
)

# Устанавливаем (опционально)
install(TARGETS Konepa
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
)
