import QtQuick
import QtQuick.Controls
import BooruVerse

Item {
    id: root
    property url previewUrl
    property url sampleUrl
    property string caption: ""
    property string borderColor: ""
    property bool favorited: false
    property bool selected: false
    property int duplicateCount: 1
    property real aspect: 1
    property bool upgrade: false
    signal tapped()
    signal peeked()
    signal selectToggled()
    signal favoriteToggled()

    function pauseThumb() { thumb.pause() }
    function resumeThumb() { thumb.resume() }

    readonly property url displayUrl: upgrade && String(sampleUrl).length > 0 ? sampleUrl : previewUrl
    readonly property int borderW: root.selected ? 4 : (root.borderColor.length ? 2 : 0)
    readonly property color frameColor: root.selected
                                        ? Theme.accent
                                        : (root.borderColor.length ? root.borderColor : "transparent")

    implicitHeight: width / Math.max(aspect, 0.2) + Theme.captionHeight

    Rectangle {
        id: frame
        anchors.fill: parent
        color: Theme.elevated
        radius: 8
        border.width: root.borderW
        border.color: root.frameColor
        clip: true

        LazyThumb {
            id: thumb
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: parent.height - Theme.captionHeight
            remoteUrl: root.displayUrl
            maxPx: root.upgrade ? 1600 : 480
            keepCached: false
            fillMode: Image.PreserveAspectFit
            // PostGrid resumes only cells near the viewport.
            paused: true

            Rectangle {
                visible: thumb.status !== Image.Ready
                anchors.fill: parent
                color: Theme.dark ? "#2C2C2E" : "#E5E5EA"
            }
        }

        Text {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: Theme.captionHeight
            text: root.duplicateCount > 1 ? root.caption + "  ×" + root.duplicateCount : root.caption
            color: Theme.secondary
            font.pixelSize: 11
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
            leftPadding: 6
            rightPadding: 6
        }

        Glyph {
            visible: root.favorited
            name: "favoritesFill"
            color: Theme.danger
            width: 14
            height: 14
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 6
        }

        MouseArea {
            visible: root.favorited
            width: 28
            height: 28
            anchors.right: parent.right
            anchors.top: parent.top
            onClicked: root.favoriteToggled()
        }
    }

    TapHandler {
        enabled: !App.peekOpen && !App.viewerOpen
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        grabPermissions: PointerHandler.ApprovesTakeOverByFlickable
                         | PointerHandler.ApprovesTakeOverByParent
        onTapped: function (eventPoint, button) {
            if (button === Qt.RightButton) {
                root.peeked()
                return
            }
            if (eventPoint.modifiers & (Qt.ControlModifier | Qt.MetaModifier))
                root.selectToggled()
            else
                root.tapped()
        }
        onLongPressed: root.peeked()
    }
}
