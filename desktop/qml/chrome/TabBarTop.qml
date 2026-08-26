import QtQuick
import QtQuick.Controls
import BooruVerse

Item {
    id: root
    implicitHeight: 44

    property int tagCount: App.selectedTags.length
    readonly property var tabs: [
        { title: "Feed", glyph: "feed", badge: 0 },
        { title: "Browse", glyph: "browse", badge: tagCount },
        { title: "Pools", glyph: "pools", badge: 0 },
        { title: "Favorites", glyph: "favorites", badge: 0 },
        { title: "Settings", glyph: "settings", badge: 0 }
    ]

    HitButton {
        id: sidebarButton
        opacity: App.tab === 1 ? 1 : 0
        enabled: App.tab === 1
        glyph: "sidebar"
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        onClicked: App.showsSidebar = !App.showsSidebar
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    SegmentedBar {
        id: tabIsland
        height: 36
        width: implicitWidth
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        model: root.tabs
        currentIndex: App.tab
        onActivated: App.tab = index
    }

    Item {
        id: rightCluster
        width: rightRow.implicitWidth
        height: 36
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter

        Row {
            id: rightRow
            anchors.right: parent.right
            spacing: 4
            height: 36

            Item {
                visible: !App.compact
                width: topChrome.implicitWidth
                height: 36
                SelectionChrome {
                    id: topChrome
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            RefreshButton {
                onClicked: App.reload()
                visible: App.tab !== 4
            }
        }
    }
}
