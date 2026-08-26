import QtQuick
import BooruVerse

Item {
    id: root
    property string chipText: ""
    property string style: "page"
    property color tint: Theme.accent
    property int count: 0
    property bool selected: false
    signal clicked()

    readonly property int hPad: style === "page" ? 11 : 8
    readonly property int vPad: style === "page" ? 6 : 4
    readonly property color displayTint: selected ? Qt.lighter(tint, 1.55) : tint

    implicitWidth: Math.ceil(labelRow.implicitWidth + hPad * 2)
    implicitHeight: Math.ceil(Math.max(28, labelRow.implicitHeight + vPad * 2))
    width: implicitWidth
    height: implicitHeight
    z: 1

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    Rectangle {
        anchors.fill: parent
        radius: root.style === "page" ? Theme.chipRadius : 12
        color: {
            if (root.style === "active")
                return Qt.rgba(0, 0.48, 1, 0.15)
            if (root.style === "suggestion")
                return Theme.dark ? "#2C2C2E" : "#1F000000"
            return Qt.rgba(root.displayTint.r, root.displayTint.g, root.displayTint.b,
                           root.selected ? 0.32 : 0.14)
        }
        border.width: root.selected ? 1.5 : 1
        border.color: root.style === "page"
                      ? Qt.rgba(root.displayTint.r, root.displayTint.g, root.displayTint.b,
                                root.selected ? 0.85 : 0.38)
                      : Qt.rgba(Theme.secondary.r, Theme.secondary.g, Theme.secondary.b, 0.25)
    }

    Row {
        id: labelRow
        spacing: 5
        anchors.centerIn: parent
        Text {
            text: root.chipText.replace(/_/g, "_\u200B")
            color: root.style === "page" ? root.displayTint : Theme.text
            font.pixelSize: root.style === "page" ? 14 : 12
            font.weight: root.selected ? Font.DemiBold : Font.Normal
            verticalAlignment: Text.AlignVCenter
        }
        Text {
            visible: root.count > 0
            text: root.count
            color: root.style === "page"
                   ? Qt.rgba(root.displayTint.r, root.displayTint.g, root.displayTint.b,
                             root.selected ? 0.9 : 0.75)
                   : Theme.secondary
            font.pixelSize: 11
            font.weight: Font.Medium
            verticalAlignment: Text.AlignVCenter
        }
    }
}
