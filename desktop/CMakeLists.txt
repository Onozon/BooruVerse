cmake_minimum_required(VERSION 3.21)
project(BooruVerseDesktop VERSION 1.3.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
set(CMAKE_AUTORCC ON)

if(NOT DEFINED CMAKE_PREFIX_PATH AND EXISTS "$ENV{HOME}/Qt/6.11.2/macos")
    set(CMAKE_PREFIX_PATH "$ENV{HOME}/Qt/6.11.2/macos")
endif()

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2 Qml Network Svg)

qt_standard_project_setup(REQUIRES 6.5)

set(APP_ICON_MAC "${CMAKE_CURRENT_SOURCE_DIR}/icons/booruverse.icns")
set(APP_ICON_WIN "${CMAKE_CURRENT_SOURCE_DIR}/icons/booruverse.rc")

qt_add_executable(BooruVerse
    src/main.cpp
    src/core/HttpClient.cpp
    src/core/ServerStore.cpp
    src/core/FavoriteStore.cpp
    src/core/SavedTagSetStore.cpp
    src/core/PersonalFeedStore.cpp
    src/core/GallerySettings.cpp
    src/core/TagIndexStore.cpp
    src/core/GalleryLayout.cpp
    src/core/SelectionStore.cpp
    src/core/DownloadStore.cpp
    src/api/BooruClient.cpp
    src/api/FeedAggregator.cpp
    src/api/PoolAggregator.cpp
    src/api/ServerProbe.cpp
    src/app/PostListModel.cpp
    src/app/SimpleListModels.cpp
    src/app/AppController.cpp
    src/app/ThumbImageProvider.cpp
    src/app/IconImageProvider.cpp
    src/app/UiTheme.cpp
)

qt_add_qml_module(BooruVerse
    URI BooruVerse
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        qml/Root.qml
        qml/chrome/TabBarBottom.qml
        qml/chrome/TabBarTop.qml
        qml/chrome/PageHeader.qml
        qml/chrome/RefreshButton.qml
        qml/pages/FeedPage.qml
        qml/pages/BrowsePage.qml
        qml/pages/BrowseSidebar.qml
        qml/pages/PoolsPage.qml
        qml/pages/FavoritesPage.qml
        qml/pages/SettingsPage.qml
        qml/gallery/PostGrid.qml
        qml/gallery/PostCell.qml
        qml/gallery/LazyThumb.qml
        qml/gallery/Viewer.qml
        qml/gallery/PeekOverlay.qml
        qml/chrome/SelectionChrome.qml
        qml/controls/Glyph.qml
        qml/controls/TagChip.qml
        qml/controls/HitButton.qml
        qml/controls/SegmentedBar.qml
        qml/controls/EmptyState.qml
        qml/controls/CompactCheck.qml
        qml/controls/CompactSwitch.qml
        qml/controls/FavoriteFolderDialog.qml
)

qt_add_resources(BooruVerse "app_icons"
    PREFIX "/icons"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/icons"
    FILES "${CMAKE_CURRENT_SOURCE_DIR}/icons/booruverse.png"
)

file(GLOB UI_ICON_SVGS "${CMAKE_CURRENT_SOURCE_DIR}/../icons/*.svg")
qt_add_resources(BooruVerse "ui_icons"
    PREFIX "/ui-icons"
    BASE "${CMAKE_CURRENT_SOURCE_DIR}/../icons"
    FILES ${UI_ICON_SVGS}
)

if(APPLE)
    set_source_files_properties(${APP_ICON_MAC} PROPERTIES
        MACOSX_PACKAGE_LOCATION "Resources"
    )
    target_sources(BooruVerse PRIVATE ${APP_ICON_MAC})
endif()

if(WIN32)
    target_sources(BooruVerse PRIVATE ${APP_ICON_WIN})
endif()

target_include_directories(BooruVerse PRIVATE src)
target_link_libraries(BooruVerse PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Qml
    Qt6::Network
    Qt6::Svg
)

set_target_properties(BooruVerse PROPERTIES
    MACOSX_BUNDLE TRUE
    MACOSX_BUNDLE_BUNDLE_NAME "BooruVerse"
    MACOSX_BUNDLE_GUI_IDENTIFIER "com.onozon.booruverse.desktop"
    MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
    MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
    MACOSX_BUNDLE_ICON_FILE booruverse.icns
    WIN32_EXECUTABLE TRUE
)

if(APPLE)
    set_target_properties(BooruVerse PROPERTIES
        INSTALL_RPATH "@executable_path/../Frameworks"
    )
endif()
