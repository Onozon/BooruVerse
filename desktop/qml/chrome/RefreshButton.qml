import QtQuick
import QtQuick.Controls
import BooruVerse

Item {
    id: root
    property bool busy: App.loading
    signal clicked()

    implicitWidth: 36
    implicitHeight: 36
    width: implicitWidth
    height: implicitHeight

    HitButton {
        anchors.fill: parent
        visible: !root.busy
        glyph: "refresh"
        onClicked: root.clicked()
    }
    BusyIndicator {
        anchors.centerIn: parent
        width: 22
        height: 22
        running: root.busy
        visible: root.busy
    }
}
