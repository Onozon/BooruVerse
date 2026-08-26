import QtQuick
import BooruVerse

Item {
    id: root

    readonly property real padTop: SafeArea.margins.top
    readonly property real padBottom: SafeArea.margins.bottom
    readonly property real padLeft: SafeArea.margins.left
    readonly property real padRight: SafeArea.margins.right
    readonly property real compactBar: 56 + padBottom

    onWidthChanged: App.windowWidth = width
    Component.onCompleted: App.windowWidth = width

    Rectangle {
        anchors.fill: parent
        color: Theme.background
    }

    Column {
        id: chrome
        anchors.fill: parent
        anchors.topMargin: root.padTop
        anchors.leftMargin: root.padLeft
        anchors.rightMargin: root.padRight
        visible: !App.viewerOpen
        enabled: !App.viewerOpen

        TabBarTop {
            width: parent.width
            visible: !App.compact
            height: visible ? implicitHeight : 0
        }

        Loader {
            id: pageLoader
            width: parent.width
            height: parent.height - (App.compact ? root.compactBar : 40)
            sourceComponent: {
                switch (App.tab) {
                case 0: return feedPage
                case 1: return browsePage
                case 2: return poolsPage
                case 3: return favoritesPage
                default: return settingsPage
                }
            }
        }

        TabBarBottom {
            width: parent.width
            visible: App.compact
            height: visible ? implicitHeight : 0
        }
    }

    Viewer {
        anchors.fill: parent
        z: 10
    }

    PeekOverlay {
        anchors.fill: parent
        z: 11
    }

    FavoriteFolderDialog {
        id: favoriteDialog
    }

    Connections {
        target: App
        function onFavoriteDialogRequested() { favoriteDialog.open() }
    }

    Component { id: feedPage; FeedPage {} }
    Component { id: browsePage; BrowsePage {} }
    Component { id: poolsPage; PoolsPage {} }
    Component { id: favoritesPage; FavoritesPage {} }
    Component { id: settingsPage; SettingsPage {} }

    Shortcut {
        sequences: [StandardKey.Refresh, "Ctrl+R"]
        enabled: !App.viewerOpen
        onActivated: App.reload()
    }

    Shortcut {
        sequence: "Escape"
        enabled: App.peekOpen
        onActivated: App.closePeek()
    }

    Shortcut {
        sequence: "Escape"
        enabled: App.viewerOpen && !App.peekOpen
        onActivated: App.closeViewer()
    }
}
