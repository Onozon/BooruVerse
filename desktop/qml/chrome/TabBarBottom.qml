import QtQuick
import BooruVerse

Item {
    id: root
    implicitHeight: 56 + SafeArea.margins.bottom

    property int tagCount: App.selectedTags.length
    readonly property var tabs: [
        { title: "Feed", glyph: "feed", badge: 0 },
        { title: "Browse", glyph: "browse", badge: tagCount },
        { title: "Pools", glyph: "pools", badge: 0 },
        { title: "Favorites", glyph: "favorites", badge: 0 },
        { title: "Settings", glyph: "settings", badge: 0 }
    ]

    Rectangle {
        id: island
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        height: 52
        radius: height / 2
        color: Theme.elevated
        border.color: Theme.separator
        border.width: 1

        Row {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 0

            Repeater {
                model: root.tabs
                delegate: Item {
                    id: tab
                    width: parent.width / 5
                    height: parent.height

                    readonly property bool selected: App.tab === index
                    readonly property int badge: Number(modelData.badge || 0)

                    Rectangle {
                        anchors.fill: parent
                        radius: height / 2
                        color: tab.selected ? Theme.accent : "transparent"
                        Behavior on color { ColorAnimation { duration: 140 } }
                    }

                    Column {
                        anchors.centerIn: parent
                        spacing: 2

                        Item {
                            width: Theme.tabIcon
                            height: Theme.tabIcon
                            anchors.horizontalCenter: parent.horizontalCenter

                            Glyph {
                                anchors.fill: parent
                                name: modelData.glyph
                                color: tab.selected ? "#FFFFFF" : Theme.text
                            }

                            Rectangle {
                                visible: tab.badge > 0
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.rightMargin: -8
                                anchors.topMargin: -6
                                width: Math.max(14, badgeLabel.implicitWidth + 6)
                                height: 14
                                radius: 7
                                color: tab.selected ? "#FFFFFF" : Theme.danger
                                z: 2

                                Text {
                                    id: badgeLabel
                                    anchors.centerIn: parent
                                    text: tab.badge > 99 ? "99+" : tab.badge
                                    color: tab.selected ? Theme.accent : "#FFFFFF"
                                    font.pixelSize: 9
                                    font.weight: Font.Bold
                                }
                            }
                        }
                        Text {
                            text: modelData.title
                            color: tab.selected ? "#FFFFFF" : Theme.text
                            font.pixelSize: Theme.tabLabel
                            font.weight: tab.selected ? Font.DemiBold : Font.Medium
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: App.tab = index
                    }
                }
            }
        }
    }
}
