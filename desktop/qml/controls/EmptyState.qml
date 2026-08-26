import QtQuick
import QtQuick.Controls
import BooruVerse

Column {
    id: root
    property string titleText: ""
    property string message: ""
    property string actionText: ""
    property string glyph: "empty"
    signal actionClicked()

    spacing: 12
    width: Math.min(parent ? parent.width - 48 : 320, 360)
    anchors.horizontalCenter: parent ? parent.horizontalCenter : undefined

    Glyph {
        name: root.glyph
        color: Theme.text
        opacity: 0.45
        width: 72
        height: 72
        anchors.horizontalCenter: parent.horizontalCenter
    }

    Text {
        text: root.titleText
        color: Theme.text
        font.pixelSize: 20
        font.weight: Font.DemiBold
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    Text {
        text: root.message
        color: Theme.secondary
        font.pixelSize: 14
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }

    Button {
        visible: root.actionText.length > 0
        text: root.actionText
        anchors.horizontalCenter: parent.horizontalCenter
        implicitHeight: Theme.hit
        onClicked: root.actionClicked()
        background: Rectangle {
            radius: 12
            color: Theme.accent
        }
        contentItem: Text {
            text: parent.text
            color: "white"
            font.pixelSize: 15
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }
}
