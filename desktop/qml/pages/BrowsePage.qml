import QtQuick
import BooruVerse

Item {
    id: root

    readonly property int islandMargin: 10
    readonly property int sidebarWidth: Math.max(Theme.sidebarMin, Math.min(Theme.sidebarMax, 300))

    Component {
        id: postGridComponent
        PostGrid {}
    }

    Item {
        anchors.fill: parent
        visible: !App.compact

        Item {
            id: sidebarSlot
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: App.showsSidebar ? root.sidebarWidth + root.islandMargin : 0
            clip: true

            Behavior on width {
                NumberAnimation { duration: 280; easing.type: Easing.InOutCubic }
            }

            Rectangle {
                width: root.sidebarWidth
                anchors.left: parent.left
                anchors.leftMargin: root.islandMargin
                anchors.top: parent.top
                anchors.topMargin: root.islandMargin
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.islandMargin
                radius: 16
                color: Theme.surface
                opacity: sidebarSlot.width > 24 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 160 } }

                BrowseSidebar {
                    anchors.fill: parent
                    anchors.margins: 4
                }
            }
        }

        Loader {
            anchors.left: sidebarSlot.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            active: !App.compact
            sourceComponent: postGridComponent
        }
    }

    Item {
        id: compactHost
        anchors.fill: parent
        visible: App.compact
        clip: true

        Column {
            id: postsPane
            width: parent.width
            height: parent.height
            x: App.browseOnSidebar ? parent.width : 0
            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }

            PageHeader {
                width: parent.width
                leftGlyph: "sidebar"
                leftText: "Search"
                busy: App.loading
                onLeftClicked: App.browseOnSidebar = true
                onRefreshClicked: App.reload()
            }

            Loader {
                width: parent.width
                height: parent.height - 52
                active: App.compact
                sourceComponent: postGridComponent
            }
        }

        Column {
            id: searchPane
            width: parent.width
            height: parent.height
            x: App.browseOnSidebar ? 0 : -parent.width
            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }

            PageHeader {
                width: parent.width
                leftGlyph: "posts"
                leftText: "Posts"
                busy: false
                onLeftClicked: App.browseOnSidebar = false
                onRefreshClicked: App.reload()
            }

            BrowseSidebar {
                width: parent.width
                height: parent.height - 52
            }
        }

        DragHandler {
            target: null
            enabled: App.compact
            onActiveChanged: {
                if (active)
                    return
                const dx = centroid.position.x - centroid.pressPosition.x
                if (!App.browseOnSidebar && dx > 60)
                    App.browseOnSidebar = true
                else if (App.browseOnSidebar && dx < -60)
                    App.browseOnSidebar = false
            }
        }
    }
}
