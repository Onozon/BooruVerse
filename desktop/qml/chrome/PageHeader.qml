import QtQuick
import QtQuick.Controls
import BooruVerse

Item {
    id: root
    property string leftGlyph: ""
    property string leftText: ""
    property bool showBack: false
    property bool showLeft: leftGlyph.length > 0 || leftText.length > 0 || showBack
    property bool showRefresh: true
    property bool busy: false
    signal leftClicked()
    signal backClicked()
    signal refreshClicked()

    implicitHeight: App.compact ? 52 : 44

    HitButton {
        visible: root.showLeft
        glyph: root.showBack ? "chevronLeft" : root.leftGlyph
        text: root.showBack ? (App.compact ? "Back" : "") : root.leftText
        anchors.left: parent.left
        anchors.leftMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        onClicked: {
            if (root.showBack)
                root.backClicked()
            else
                root.leftClicked()
        }
    }

    Row {
        id: rightCluster
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4
        height: 36

        Item {
            visible: App.compact
            width: chrome.implicitWidth
            height: 36
            SelectionChrome {
                id: chrome
                anchors.centerIn: parent
            }
        }

        Item {
            visible: root.showRefresh
            width: 36
            height: 36

            HitButton {
                anchors.fill: parent
                visible: !root.busy
                glyph: "refresh"
                onClicked: root.refreshClicked()
            }
            BusyIndicator {
                anchors.centerIn: parent
                width: 22
                height: 22
                running: root.busy
                visible: root.busy
            }
        }
    }
}
