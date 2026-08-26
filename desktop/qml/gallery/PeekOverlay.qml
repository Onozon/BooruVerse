import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import BooruVerse

Item {
    id: root
    visible: App.peekOpen || opacity > 0.01
    opacity: App.peekOpen ? 1 : 0
    z: 9
    Behavior on opacity { NumberAnimation { duration: 160 } }

    Rectangle {
        anchors.fill: parent
        color: "#73000000"
        MouseArea {
            anchors.fill: parent
            onClicked: App.closePeek()
        }
    }

    readonly property real cardW: Math.min(width - 32, App.compact ? 360 : 640)
    readonly property real cardH: Math.min(height * 0.78, App.compact ? 520 : 480)

    Rectangle {
        id: card
        width: root.cardW
        height: root.cardH
        radius: 16
        color: Theme.surface
        anchors.centerIn: parent
        clip: true

        MouseArea { anchors.fill: parent }

        ColumnLayout {
            visible: App.compact
            anchors.fill: parent
            spacing: 0
            z: 1

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(card.height * 0.36, 200)
                Layout.minimumHeight: 120
                LazyThumb {
                    anchors.fill: parent
                    anchors.margins: 8
                    remoteUrl: App.peekUrl
                    maxPx: 900
                    fillMode: Image.PreserveAspectFit
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                Text {
                    text: "Tags"
                    color: Theme.text
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: App.peekMeta
                    color: Theme.secondary
                    font.pixelSize: 12
                    anchors.right: closePeek.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                }
                HitButton {
                    id: closePeek
                    glyph: "close"
                    minSize: 36
                    width: 36
                    height: 36
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: App.closePeek()
                }
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                clip: true
                contentHeight: peekTagsCol.height
                boundsBehavior: Flickable.StopAtBounds
                PeekTagList {
                    id: peekTagsCol
                    width: parent.width
                }
            }

            PeekActions {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.bottomMargin: 6
            }
        }

        ColumnLayout {
            visible: !App.compact
            anchors.fill: parent
            spacing: 0
            z: 1

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    LazyThumb {
                        anchors.fill: parent
                        anchors.margins: 8
                        remoteUrl: App.peekUrl
                        maxPx: 1200
                        fillMode: Image.PreserveAspectFit
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.fillHeight: true
                    color: Theme.separator
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: 0

                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        Text {
                            text: "Tags"
                            color: Theme.text
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: App.peekMeta
                            color: Theme.secondary
                            font.pixelSize: 12
                            anchors.right: closePeek2.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        HitButton {
                            id: closePeek2
                            glyph: "close"
                            minSize: 36
                            width: 36
                            height: 36
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: App.closePeek()
                        }
                    }

                    Flickable {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 12
                        Layout.rightMargin: 12
                        clip: true
                        contentHeight: peekTagsCol2.height
                        boundsBehavior: Flickable.StopAtBounds
                        PeekTagList {
                            id: peekTagsCol2
                            width: parent.width
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.separator
            }

            PeekActions {
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                Layout.bottomMargin: 4
            }
        }
    }

    component PeekTagList: Column {
        spacing: 8
        Repeater {
            model: App.peekTagGroups
            delegate: Column {
                width: parent.width
                spacing: 6
                Text {
                    text: modelData.title
                    color: modelData.color
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Flow {
                    width: parent.width
                    spacing: 7
                    Repeater {
                        model: modelData.tags
                        delegate: TagChip {
                            chipText: modelData.name
                            style: "page"
                            tint: modelData.typeColor
                            selected: !!modelData.selected
                            onClicked: App.toggleTag(modelData.name)
                        }
                    }
                }
            }
        }
    }

    component PeekActions: Item {
        id: actionsRoot
        implicitHeight: actionFlow.implicitHeight + 12

        Flow {
            id: actionFlow
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 16
            spacing: 6

            HitButton {
                glyph: App.peekFavorited ? "favoritesFill" : "favorites"
                text: App.peekFavorited ? "Favorited" : "Favorite"
                glyphColor: App.peekFavorited ? Theme.danger : Theme.text
                minSize: 36
                height: 36
                onClicked: App.peekFavorite()
            }
            HitButton {
                glyph: "save"
                text: "Save As"
                minSize: 36
                height: 36
                onClicked: peekSave.open()
            }
            HitButton {
                glyph: "site"
                text: "Site"
                minSize: 36
                height: 36
                onClicked: App.openPeekSite()
            }
            HitButton {
                glyph: "checkCircle"
                text: "Select"
                minSize: 36
                height: 36
                onClicked: App.peekSelect()
            }
        }
    }

    FileDialog {
        id: peekSave
        fileMode: FileDialog.SaveFile
        currentFile: "file:" + App.suggestedPeekName()
        onAccepted: {
            const path = selectedFile.toString().replace("file://", "")
            App.savePeekFile(path)
        }
    }
}
