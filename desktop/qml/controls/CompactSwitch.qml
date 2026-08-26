import QtQuick
import BooruVerse

Item {
    id: root
    property bool checked: false
    signal toggled(bool checked)

    implicitWidth: 46
    implicitHeight: 28
    width: implicitWidth
    height: implicitHeight

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: root.checked ? Theme.accent : (Theme.dark ? "#3A3A3C" : "#E5E5EA")

        Rectangle {
            width: 24
            height: 24
            radius: 12
            color: "white"
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 2 : 2
            Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.toggled(!root.checked)
    }
}
