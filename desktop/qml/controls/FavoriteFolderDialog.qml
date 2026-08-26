import QtQuick
import QtQuick.Controls
import BooruVerse

Popup {
    id: root
    modal: true
    anchors.centerIn: Overlay.overlay
    width: Math.min(420, (parent ? parent.width : 420) - 24)
    padding: 16
    background: Rectangle {
        color: Theme.surface
        radius: 14
        border.color: Theme.separator
    }

    onAboutToShow: {
        const names = []
        for (let i = 0; i < App.folders.count; ++i)
            names.push(App.folders.folderAt(i).name)
        names.push("New folder")
        folderBox.model = names
        folderBox.currentIndex = Math.min(App.folders.indexOfId(App.lastFavoriteFolderId), App.folders.count - 1)
        newName.text = ""
    }

    Column {
        width: parent.width
        spacing: 12
        Text {
            text: "Add to Favorites"
            color: Theme.text
            font.pixelSize: 16
            font.weight: Font.DemiBold
        }
        ComboBox {
            id: folderBox
            width: parent.width
        }
        TextField {
            id: newName
            width: parent.width
            visible: folderBox.currentIndex >= App.folders.count
            placeholderText: "Folder name"
        }
        Row {
            spacing: 8
            layoutDirection: Qt.RightToLeft
            width: parent.width
            HitButton {
                text: "Add"
                highlighted: true
                onClicked: {
                    if (folderBox.currentIndex >= App.folders.count) {
                        if (!newName.text.trim().length)
                            return
                        App.confirmFavoriteNew(newName.text)
                    } else {
                        App.confirmFavorite(App.folders.folderAt(folderBox.currentIndex).id)
                    }
                    root.close()
                }
            }
            HitButton {
                text: "Cancel"
                onClicked: root.close()
            }
        }
    }
}
