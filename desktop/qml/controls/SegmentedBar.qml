import QtQuick
import QtQuick.Controls
import BooruVerse

Item {
    id: root
    property var model: []
    property int currentIndex: 0
    signal activated(int index)

    property real _maxContent: 0
    readonly property int segmentPad: 28
    readonly property int segmentMin: 72
    readonly property int count: Math.max(root.model.length, 1)
    readonly property real segmentWidth: Math.max(_maxContent, segmentMin)

    implicitHeight: App.compact ? 44 : 36
    implicitWidth: 6 + count * segmentWidth

    onModelChanged: _maxContent = 0

    function noteContent(w) {
        if (w > _maxContent)
            _maxContent = w
    }

    function badgeFor(data) {
        if (typeof data === "object" && data && data.badge !== undefined)
            return Number(data.badge)
        return 0
    }

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: Theme.elevated
        border.color: Theme.separator
        border.width: 1
    }

    Row {
        id: segmentRow
        anchors.fill: parent
        anchors.margins: 3
        spacing: 0

        Repeater {
            model: root.model
            delegate: Item {
                id: segment
                width: parent.width / root.count
                height: parent.height

                readonly property bool selected: root.currentIndex === index
                readonly property string label: typeof modelData === "string" ? modelData : String(modelData.title || "")
                readonly property string glyphName: typeof modelData === "string" ? "" : String(modelData.glyph || "")
                readonly property int badge: root.badgeFor(modelData)

                Rectangle {
                    anchors.fill: parent
                    radius: height / 2
                    color: segment.selected ? Theme.accent : "transparent"
                    Behavior on color { ColorAnimation { duration: 140 } }
                }

                Row {
                    id: contentRow
                    anchors.centerIn: parent
                    spacing: 5
                    height: parent.height

                    Item {
                        width: 14
                        height: 14
                        visible: segment.glyphName.length > 0
                        anchors.verticalCenter: parent.verticalCenter

                        Glyph {
                            anchors.fill: parent
                            name: segment.glyphName
                            color: segment.selected ? "#FFFFFF" : Theme.text
                        }

                        Rectangle {
                            visible: segment.badge > 0
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -7
                            anchors.topMargin: -6
                            width: Math.max(14, badgeLabel.implicitWidth + 6)
                            height: 14
                            radius: 7
                            color: segment.selected ? "#FFFFFF" : Theme.danger
                            border.width: segment.selected ? 0 : 1
                            border.color: Theme.surface
                            z: 2

                            Text {
                                id: badgeLabel
                                anchors.centerIn: parent
                                text: segment.badge > 99 ? "99+" : segment.badge
                                color: segment.selected ? Theme.accent : "#FFFFFF"
                                font.pixelSize: 9
                                font.weight: Font.Bold
                            }
                        }
                    }
                    Text {
                        text: segment.label
                        color: segment.selected ? "#FFFFFF" : Theme.text
                        font.pixelSize: App.compact ? 14 : 12
                        font.weight: segment.selected ? Font.DemiBold : Font.Medium
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Component.onCompleted: root.noteContent(contentRow.implicitWidth + root.segmentPad)
                    onImplicitWidthChanged: root.noteContent(contentRow.implicitWidth + root.segmentPad)
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        root.currentIndex = index
                        root.activated(index)
                    }
                }
            }
        }
    }
}
