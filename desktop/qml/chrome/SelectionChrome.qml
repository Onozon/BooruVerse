import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import BooruVerse

Item {
    id: root
    readonly property bool active: App.selectedPosts.count > 0 || App.downloads.visible
    readonly property int chromeSize: 36
    implicitWidth: active ? row.implicitWidth : 0
    implicitHeight: chromeSize
    width: implicitWidth
    height: chromeSize
    visible: active

    onVisibleChanged: {
        if (!visible) {
            selectedPopup.close()
            downloadsPopup.close()
        }
    }

    function clampPopup(popup, preferredWidth) {
        const win = ApplicationWindow.window
        const margin = 12
        const maxW = win ? Math.max(160, win.width - margin * 2) : preferredWidth
        popup.width = Math.min(preferredWidth, maxW)
        if (!win || !popup.parent)
            return
        const origin = root.mapToItem(popup.parent, 0, 0)
        const preferredX = origin.x + root.width - popup.width
        popup.x = Math.max(margin, Math.min(preferredX, win.width - margin - popup.width))
        popup.y = origin.y + root.height + 6
    }

    Row {
        id: row
        spacing: 4
        height: root.chromeSize
        anchors.verticalCenter: parent.verticalCenter

        HitButton {
            visible: App.selectedPosts.count > 0
            glyph: "checkCircle"
            text: App.selectedPosts.count
            minSize: root.chromeSize
            width: Math.max(root.chromeSize, implicitWidth)
            height: root.chromeSize
            onClicked: selectedPopup.open()
        }

        HitButton {
            visible: App.downloads.visible
            glyph: "download"
            glyphColor: App.downloads.allSucceeded ? "#34C759" : Theme.text
            minSize: root.chromeSize
            width: root.chromeSize
            height: root.chromeSize
            onClicked: downloadsPopup.open()
        }
    }

    Connections {
        target: App.selectedPosts
        function onCountChanged() {
            if (App.selectedPosts.count === 0)
                selectedPopup.close()
        }
    }

    Connections {
        target: App.downloads
        function onStatusChanged() {
            if (!App.downloads.visible)
                downloadsPopup.close()
        }
        function onCountChanged() {
            if (App.downloads.count === 0)
                downloadsPopup.close()
        }
    }

    Popup {
        id: selectedPopup
        parent: Overlay.overlay
        padding: 10
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        readonly property int rowH: 52
        readonly property int rowGap: 4
        readonly property int headerH: 22
        readonly property int actionsH: 36
        readonly property int gaps: 16

        width: Math.min(360, (ApplicationWindow.window ? ApplicationWindow.window.width : 360) - 24)
        height: {
            const n = Math.max(App.selectedPosts.count, 0)
            const list = n * rowH + Math.max(0, n - 1) * rowGap
            return Math.min(420, padding * 2 + headerH + gaps + list + actionsH)
        }

        onAboutToShow: root.clampPopup(selectedPopup, 360)
        onWidthChanged: if (visible) root.clampPopup(selectedPopup, 360)
        onHeightChanged: if (visible) root.clampPopup(selectedPopup, 360)

        background: Rectangle {
            color: Theme.surface
            radius: 12
            border.color: Theme.separator
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            Text {
                text: "Selected"
                color: Theme.text
                font.pixelSize: 15
                font.weight: Font.DemiBold
                Layout.fillWidth: true
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: App.selectedPosts
                spacing: selectedPopup.rowGap
                delegate: Item {
                    width: ListView.view.width
                    height: selectedPopup.rowH
                    Row {
                        anchors.fill: parent
                        spacing: 8
                        LazyThumb {
                            width: 52
                            height: 52
                            remoteUrl: model.previewUrl
                            maxPx: 160
                            fillMode: Image.PreserveAspectCrop
                        }
                        Text {
                            text: model.serverId + " #" + model.postId
                            color: Theme.text
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            width: parent.width - 96
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        HitButton {
                            glyph: "close"
                            minSize: 36
                            width: 36
                            height: 36
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: App.selectedPosts.removeAt(index)
                        }
                    }
                }
            }

            Row {
                spacing: 6
                Layout.fillWidth: true
                HitButton {
                    text: "Download"
                    glyph: "download"
                    minSize: 36
                    height: 36
                    onClicked: {
                        if (App.askDownloadFolder)
                            downloadFolder.open()
                        else
                            App.enqueueDownloads(App.downloadFolder)
                        selectedPopup.close()
                    }
                }
                HitButton {
                    text: "Favorites"
                    glyph: "favorites"
                    minSize: 36
                    height: 36
                    onClicked: {
                        App.requestFavoriteSelected()
                        selectedPopup.close()
                    }
                }
                HitButton {
                    text: "Clear"
                    minSize: 36
                    height: 36
                    onClicked: {
                        App.selectedPosts.clear()
                        selectedPopup.close()
                    }
                }
            }
        }
    }

    Popup {
        id: downloadsPopup
        parent: Overlay.overlay
        padding: 10
        modal: false
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        readonly property int rowH: 52
        readonly property int rowGap: 4
        readonly property int headerH: 36
        readonly property int gaps: 8

        width: Math.min(380, (ApplicationWindow.window ? ApplicationWindow.window.width : 380) - 24)
        height: {
            const n = Math.max(App.downloads.count, 0)
            const list = n * rowH + Math.max(0, n - 1) * rowGap
            return Math.min(420, padding * 2 + headerH + gaps + list)
        }

        onAboutToShow: root.clampPopup(downloadsPopup, 380)
        onWidthChanged: if (visible) root.clampPopup(downloadsPopup, 380)
        onHeightChanged: if (visible) root.clampPopup(downloadsPopup, 380)

        background: Rectangle {
            color: Theme.surface
            radius: 12
            border.color: Theme.separator
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "Downloads"
                    color: Theme.text
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    Layout.fillWidth: true
                    verticalAlignment: Text.AlignVCenter
                }
                HitButton {
                    visible: App.downloads.hasFailed
                    text: "Retry"
                    minSize: 36
                    height: 36
                    onClicked: App.downloads.retryFailed()
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                model: App.downloads
                spacing: downloadsPopup.rowGap
                delegate: Item {
                    width: ListView.view.width
                    height: downloadsPopup.rowH
                    MouseArea {
                        anchors.fill: parent
                        onClicked: App.downloads.openItem(index)
                    }
                    Row {
                        anchors.fill: parent
                        spacing: 8
                        LazyThumb {
                            width: 52
                            height: 52
                            remoteUrl: model.previewUrl
                            maxPx: 160
                            fillMode: Image.PreserveAspectCrop
                        }
                        Column {
                            width: parent.width - 60
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: model.fileName
                                color: Theme.text
                                font.pixelSize: 13
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: model.status === 2 ? (model.errorText || "Failed")
                                    : model.status === 3 ? "Done"
                                    : model.status === 1 ? Math.round(model.progress * 100) + "%"
                                    : "Queued"
                                color: model.status === 2 ? Theme.danger : Theme.secondary
                                font.pixelSize: 11
                            }
                            Rectangle {
                                visible: model.status === 1
                                width: parent.width
                                height: 3
                                radius: 1
                                color: Theme.separator
                                Rectangle {
                                    width: parent.width * model.progress
                                    height: parent.height
                                    color: Theme.accent
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    FolderDialog {
        id: downloadFolder
        onAccepted: App.enqueueDownloads(selectedFolder.toString())
    }
}
