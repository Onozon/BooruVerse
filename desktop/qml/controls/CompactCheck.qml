import QtQuick
import BooruVerse

Item {
    id: root
    property bool checked: false
    signal toggled(bool checked)

    width: 22
    height: 22

    Glyph {
        anchors.fill: parent
        name: root.checked ? "checkCircle" : "checkBlank"
        color: Theme.text
    }

    MouseArea {
        anchors.fill: parent
        anchors.margins: -8
        onClicked: root.toggled(!root.checked)
    }
}
