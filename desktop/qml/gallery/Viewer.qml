import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import BooruVerse

Rectangle {
    id: root
    color: "black"
    visible: App.viewerOpen || opacity > 0.01
    opacity: App.viewerOpen ? 1 : 0
    focus: App.viewerOpen
    Behavior on opacity { NumberAnimation { duration: 180 } }

    property bool chromeVisible: false
    property bool tagsVisible: false
    property real zoom: 1

    onVisibleChanged: {
        if (visible) {
            chromeVisible = false
            tagsVisible = false
            imageFlick.resetView()
            forceActiveFocus()
        }
    }

    Connections {
        target: App
        function onViewerChanged() {
            imageFlick.resetView()
        }
    }

    Keys.onPressed: function (event) {
        if (!App.viewerOpen)
            return
        if (event.key === Qt.Key_Escape)
            App.closeViewer()
        else if (event.key === Qt.Key_Left)
            App.viewerMove(-1)
        else if (event.key === Qt.Key_Right)
            App.viewerMove(1)
        else if (event.key === Qt.Key_F)
            App.toggleViewerFavorite()
        else if (event.key === Qt.Key_S)
            saveDialog.open()
        else if (event.key === Qt.Key_T)
            tagsVisible = !tagsVisible
        else
            return
        event.accepted = true
    }

    Flickable {
        id: imageFlick
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        boundsMovement: Flickable.StopAtBounds
        interactive: root.zoom > 1.02
        contentWidth: Math.max(width, canvas.width)
        contentHeight: Math.max(height, canvas.height)

        readonly property real fit: {
            const iw = picture.implicitWidth
            const ih = picture.implicitHeight
            if (iw <= 0 || ih <= 0)
                return 1
            return Math.min(width / iw, height / ih)
        }

        function clamp() {
            contentX = Math.max(0, Math.min(contentX, Math.max(0, contentWidth - width)))
            contentY = Math.max(0, Math.min(contentY, Math.max(0, contentHeight - height)))
        }

        function zoomAround(nextZoom, viewX, viewY) {
            const z = Math.max(1, Math.min(5, nextZoom))
            const oldW = Math.max(1, picture.width)
            const oldH = Math.max(1, picture.height)
            const rx = (contentX + viewX - picture.x) / oldW
            const ry = (contentY + viewY - picture.y) / oldH
            root.zoom = z
            contentX = picture.x + rx * picture.width - viewX
            contentY = picture.y + ry * picture.height - viewY
            clamp()
        }

        function resetView() {
            root.zoom = 1
            contentX = 0
            contentY = 0
        }

        Item {
            id: canvas
            width: Math.max(imageFlick.width, picture.width)
            height: Math.max(imageFlick.height, picture.height)

            Image {
                id: picture
                anchors.centerIn: parent
                width: implicitWidth > 0 ? implicitWidth * imageFlick.fit * root.zoom : imageFlick.width
                height: implicitHeight > 0 ? implicitHeight * imageFlick.fit * root.zoom : imageFlick.height
                source: App.viewerUrl
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                cache: false
                mipmap: true
                smooth: true
            }
        }

        PinchHandler {
            id: pinch
            target: null
            minimumPointCount: 2
            property real startZoom: 1
            onActiveChanged: {
                if (active) {
                    startZoom = root.zoom
                    swipe.pinchGen = swipe.pinchGen + 1
                }
            }
            onScaleChanged: {
                if (active)
                    imageFlick.zoomAround(startZoom * scale, centroid.position.x, centroid.position.y)
            }
        }

        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: function (event) {
                imageFlick.zoomAround(root.zoom + (event.angleDelta.y > 0 ? 0.2 : -0.2), event.x, event.y)
                event.accepted = true
            }
        }

        TapHandler {
            onTapped: {
                if (root.zoom > 1.05)
                    return
                root.chromeVisible = !root.chromeVisible
                if (!root.chromeVisible)
                    root.tagsVisible = false
            }
        }

        DragHandler {
            id: swipe
            target: null
            enabled: root.zoom <= 1.05 && !pinch.active
            minimumPointCount: 1
            maximumPointCount: 1
            property int pinchGen: 0
            property int genAtPress: 0
            onActiveChanged: {
                if (active) {
                    genAtPress = pinchGen
                    return
                }
                if (pinch.active || pinchGen !== genAtPress)
                    return
                const dx = centroid.position.x - centroid.pressPosition.x
                const dy = centroid.position.y - centroid.pressPosition.y
                if (Math.abs(dx) < 100)
                    return
                if (Math.abs(dx) < Math.abs(dy) * 1.4)
                    return
                if (dx > 0)
                    App.viewerMove(-1)
                else
                    App.viewerMove(1)
            }
        }
    }

    Rectangle {
        visible: picture.status === Image.Loading
        anchors.centerIn: parent
        width: 160
        height: 8
        radius: 4
        color: "#33FFFFFF"
        Rectangle {
            width: parent.width * picture.progress
            height: parent.height
            radius: 4
            color: Theme.accent
        }
    }

    HitButton {
        opacity: root.chromeVisible ? 1 : 0
        enabled: root.chromeVisible
        glyph: "close"
        glyphColor: "white"
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 12 + SafeArea.margins.top
        anchors.rightMargin: 12 + SafeArea.margins.right
        width: Theme.closeSize
        height: Theme.closeSize
        onClicked: App.closeViewer()
        background: Rectangle {
            radius: width / 2
            color: "#66000000"
        }
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    HitButton {
        opacity: root.chromeVisible ? 1 : 0
        enabled: root.chromeVisible
        glyph: "tags"
        glyphColor: "white"
        highlighted: root.tagsVisible
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 12 + SafeArea.margins.top
        anchors.rightMargin: 12 + Theme.closeSize + 8 + SafeArea.margins.right
        width: Theme.closeSize
        height: Theme.closeSize
        onClicked: root.tagsVisible = !root.tagsVisible
        background: Rectangle {
            radius: width / 2
            color: "#66000000"
        }
        Behavior on opacity { NumberAnimation { duration: 160 } }
    }

    Rectangle {
        id: tagsPane
        opacity: root.chromeVisible && root.tagsVisible ? 1 : 0
        visible: opacity > 0.01
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: actionBar.opacity > 0.01 ? actionBar.top : parent.bottom
        anchors.topMargin: Theme.closeSize + 20 + SafeArea.margins.top
        width: Math.min(App.compact ? parent.width : 300, parent.width * (App.compact ? 1 : 0.34))
        color: "#E6000000"
        Behavior on opacity { NumberAnimation { duration: 180 } }

        Flickable {
            anchors.fill: parent
            anchors.margins: 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentHeight: tagColumn.height
            Column {
                id: tagColumn
                width: parent.width
                spacing: 8
                Text {
                    text: App.viewerMeta
                    color: "#CCFFFFFF"
                    font.pixelSize: 12
                    width: parent.width
                    wrapMode: Text.WordWrap
                }
                Repeater {
                    model: App.viewerTags
                    delegate: TagChip {
                        chipText: model.name
                        style: "page"
                        tint: model.typeColor
                        selected: model.selected
                        onClicked: App.toggleTag(model.name)
                    }
                }
            }
        }
    }

    Rectangle {
        id: actionBar
        opacity: root.chromeVisible ? 1 : 0
        visible: opacity > 0.01
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Theme.actionBar + SafeArea.margins.bottom
        color: "#E6000000"
        Behavior on opacity { NumberAnimation { duration: 160 } }

        Flickable {
            id: actionFlick
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            anchors.topMargin: 8
            height: 40
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: Math.max(width, actionRow.implicitWidth)
            contentHeight: height
            interactive: contentWidth > width + 1
            flickableDirection: Flickable.HorizontalFlick

            Row {
                id: actionRow
                spacing: 6
                height: parent.height
                // Center when the row fits; otherwise start at 0 and allow flick.
                x: Math.max(0, (actionFlick.width - implicitWidth) / 2)

                HitButton {
                    glyph: "chevronLeft"
                    glyphColor: "white"
                    minSize: 36
                    width: 36
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: App.viewerMove(-1)
                }
                HitButton {
                    glyph: App.viewerFavorited ? "favoritesFill" : "favorites"
                    glyphColor: App.viewerFavorited ? Theme.danger : "white"
                    minSize: 36
                    width: 36
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: App.toggleViewerFavorite()
                }
                HitButton {
                    glyph: "save"
                    glyphColor: "white"
                    minSize: 36
                    width: 36
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: saveDialog.open()
                }
                HitButton {
                    visible: App.viewerHasOriginal
                    text: "Original"
                    glyphColor: "white"
                    minSize: 36
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: App.loadViewerOriginal()
                }
                HitButton {
                    glyph: "site"
                    glyphColor: "white"
                    minSize: 36
                    width: 36
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: App.openViewerSite()
                }
                HitButton {
                    glyph: "chevronRight"
                    glyphColor: "white"
                    minSize: 36
                    width: 36
                    height: 36
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: App.viewerMove(1)
                }
            }
        }
    }

    FileDialog {
        id: saveDialog
        fileMode: FileDialog.SaveFile
        currentFile: "file:" + App.suggestedSaveName()
        onAccepted: {
            const path = selectedFile.toString().replace("file://", "")
            App.saveViewerFile(path)
        }
    }
}
