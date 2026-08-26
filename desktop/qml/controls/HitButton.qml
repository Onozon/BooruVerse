import QtQuick
import QtQuick.Controls
import BooruVerse

AbstractButton {
    id: root
    property string glyph: ""
    property color glyphColor: enabled ? Theme.text : Theme.secondary
    property bool highlighted: false
    property int minSize: App.compact ? Theme.hit : Theme.hitRegular

    implicitWidth: Math.max(minSize, inner.implicitWidth + 16)
    implicitHeight: Math.max(minSize, 18 + 8)
    padding: 0
    scale: down ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }

    contentItem: Item {
        implicitWidth: inner.implicitWidth
        implicitHeight: 18

        Row {
            id: inner
            spacing: 6
            anchors.centerIn: parent
            height: 18

            Glyph {
                visible: root.glyph.length > 0
                name: root.glyph
                color: root.glyphColor
                width: 18
                height: 18
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                visible: root.text.length > 0
                text: root.text
                color: root.glyphColor
                font.pixelSize: App.compact ? 15 : 13
                font.weight: root.highlighted || root.checked ? Font.DemiBold : Font.Normal
                height: 18
                verticalAlignment: Text.AlignVCenter
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    background: Rectangle {
        radius: 10
        color: root.down ? Theme.elevated : (root.highlighted || root.checked ? Qt.rgba(0, 0.48, 1, 0.12) : "transparent")
    }
}
