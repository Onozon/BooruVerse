import QtQuick
import QtQuick.Controls
import BooruVerse

Item {
    id: root
    readonly property int islandMargin: 10
    readonly property int sidebarWidth: Math.max(Theme.sidebarMin, Math.min(Theme.sidebarMax, 280))

    Component {
        id: postGridComponent
        PostGrid {}
    }

    Item {
        anchors.fill: parent
        visible: !App.compact

        Rectangle {
            id: folderPane
            width: root.sidebarWidth
            anchors.left: parent.left
            anchors.leftMargin: root.islandMargin
            anchors.top: parent.top
            anchors.topMargin: root.islandMargin
            anchors.bottom: parent.bottom
            anchors.bottomMargin: root.islandMargin
            radius: 16
            color: Theme.surface

            FolderSidebar { anchors.fill: parent }
        }

        Loader {
            anchors.left: folderPane.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            active: !App.compact
            sourceComponent: postGridComponent
        }
    }

    Item {
        anchors.fill: parent
        visible: App.compact
        clip: true

        Column {
            width: parent.width
            height: parent.height
            x: App.favoritesOnSidebar ? parent.width : 0
            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }

            PageHeader {
                width: parent.width
                leftGlyph: "folder"
                leftText: "Folders"
                busy: App.loading
                onLeftClicked: App.favoritesOnSidebar = true
                onRefreshClicked: App.reload()
            }
            Loader {
                width: parent.width
                height: parent.height - 52
                active: App.compact
                sourceComponent: postGridComponent
            }
        }

        Column {
            width: parent.width
            height: parent.height
            x: App.favoritesOnSidebar ? 0 : -parent.width
            Behavior on x { NumberAnimation { duration: 280; easing.type: Easing.InOutCubic } }

            PageHeader {
                width: parent.width
                leftGlyph: "posts"
                leftText: "Posts"
                busy: false
                onLeftClicked: App.favoritesOnSidebar = false
                onRefreshClicked: App.reload()
            }
            FolderSidebar {
                width: parent.width
                height: parent.height - 52
            }
        }
    }

    component FolderSidebar: Item {
        readonly property int pad: 8

        Column {
            anchors.fill: parent
            anchors.margins: parent.pad
            spacing: 8

            Item {
                width: parent.width
                height: 36

                Text {
                    text: "Folders"
                    color: Theme.text
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    anchors.left: parent.left
                    anchors.right: addFolder.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                }
                HitButton {
                    id: addFolder
                    glyph: "plus"
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: {
                        newFolderField.text = ""
                        newFolderDialog.open()
                    }
                }
            }

            ListView {
                width: parent.width
                height: parent.height - 44
                clip: true
                model: App.folders
                currentIndex: App.folders.indexOfId(App.favoriteFolderId)
                delegate: ItemDelegate {
                    width: ListView.view.width
                    implicitHeight: 44
                    padding: 0
                    leftPadding: 8
                    rightPadding: 8
                    topPadding: 0
                    bottomPadding: 0
                    highlighted: model.folderId === App.favoriteFolderId
                    onClicked: {
                        App.favoriteFolderId = model.folderId
                        if (App.compact)
                            App.favoritesOnSidebar = false
                    }
                    onPressAndHold: folderMenu.open()
                    background: Rectangle {
                        radius: 8
                        color: parent.highlighted
                               ? (Theme.dark ? "#3A3A3C" : "#E5E5EA")
                               : "transparent"
                    }
                    contentItem: Item {
                        implicitHeight: 44

                        Glyph {
                            id: folderIcon
                            name: "folder"
                            width: 16
                            height: 16
                            color: Theme.text
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: model.name
                            color: Theme.text
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            anchors.left: folderIcon.right
                            anchors.leftMargin: 8
                            anchors.right: countLabel.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            id: countLabel
                            text: model.postCount
                            color: Theme.secondary
                            font.pixelSize: 12
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Menu {
                        id: folderMenu
                        MenuItem {
                            text: "Rename"
                            onTriggered: {
                                renameField.text = model.name
                                renameDialog.folderId = model.folderId
                                renameDialog.open()
                            }
                        }
                        MenuItem {
                            text: "Delete"
                            enabled: !model.isDefault
                            onTriggered: {
                                deleteDialog.folderId = model.folderId
                                deleteDialog.open()
                            }
                        }
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        onTapped: folderMenu.open()
                    }
                }
            }
        }

        Dialog {
            id: newFolderDialog
            title: "New Folder"
            modal: true
            standardButtons: Dialog.Save | Dialog.Cancel
            TextField {
                id: newFolderField
                width: parent.width
                placeholderText: "Folder name"
            }
            onAccepted: App.createFavoriteFolder(newFolderField.text)
        }

        Dialog {
            id: renameDialog
            property string folderId: ""
            title: "Rename Folder"
            modal: true
            standardButtons: Dialog.Save | Dialog.Cancel
            TextField { id: renameField; width: parent.width }
            onAccepted: App.renameFavoriteFolder(folderId, renameField.text)
        }

        Dialog {
            id: deleteDialog
            property string folderId: ""
            title: "Delete Folder"
            modal: true
            width: Math.min(360, root.width - 24)
            Label {
                text: "Delete the pictures in this folder, or move them to Favorites?"
                wrapMode: Text.WordWrap
                width: parent.width
                color: Theme.text
            }
            footer: DialogButtonBox {
                Button {
                    text: "Delete pictures"
                    DialogButtonBox.buttonRole: DialogButtonBox.DestructiveRole
                    onClicked: {
                        App.deleteFavoriteFolder(deleteDialog.folderId, true)
                        deleteDialog.close()
                    }
                }
                Button {
                    text: "Move to Favorites"
                    DialogButtonBox.buttonRole: DialogButtonBox.AcceptRole
                    onClicked: {
                        App.deleteFavoriteFolder(deleteDialog.folderId, false)
                        deleteDialog.close()
                    }
                }
                Button {
                    text: "Cancel"
                    DialogButtonBox.buttonRole: DialogButtonBox.RejectRole
                    onClicked: deleteDialog.close()
                }
            }
        }
    }
}
