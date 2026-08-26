import QtQuick
import BooruVerse

Item {
    Column {
        anchors.fill: parent

        Item { width: 1; height: 8 }

        Item {
            id: channelRow
            width: parent.width
            height: channelBar.implicitHeight

            SegmentedBar {
                id: channelBar
                width: App.compact
                       ? Math.max(0, parent.width - 24 - rightCluster.width)
                       : Math.min(parent.width - 32, 420)
                x: App.compact ? 16 : (parent.width - width) / 2
                currentIndex: App.feedChannel
                model: ["Personal", "Day", "Week", "Month"]
                onActivated: App.feedChannel = index
            }

            Row {
                id: rightCluster
                visible: App.compact
                spacing: 4
                height: 36
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter

                SelectionChrome {
                    id: feedChrome
                    anchors.verticalCenter: parent.verticalCenter
                }
                RefreshButton {
                    onClicked: App.reload()
                }
            }
        }

        Item { width: 1; height: 8 }

        Item {
            width: parent.width
            height: parent.height - channelRow.height - 16

            EmptyState {
                visible: App.personalEmpty
                anchors.centerIn: parent
                titleText: "Personal Feed"
                message: "Choose saved tag sets to build a mixed feed. Overlapping posts appear once, newest first."
                actionText: "Choose Tag Sets"
                glyph: "empty"
                onActionClicked: App.tab = 4
            }

            PostGrid {
                anchors.fill: parent
                visible: !App.personalEmpty
            }
        }
    }
}
