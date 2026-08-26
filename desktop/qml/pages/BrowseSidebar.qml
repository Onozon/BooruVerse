import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BooruVerse

Item {
    id: root

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Column {
            Layout.fillWidth: true
            Layout.topMargin: 12
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            spacing: 10

            RowLayout {
                width: parent.width
                spacing: 8
                TextField {
                    id: tagField
                    Layout.fillWidth: true
                    Layout.preferredHeight: App.compact ? Theme.hit : 34
                    placeholderText: "Add tag…"
                    text: App.tagInput
                    onTextChanged: App.tagInput = text
                    onAccepted: App.commitTagInput()
                }
                Button {
                    text: "Add"
                    enabled: App.tagInput.trim().length > 0
                    implicitHeight: App.compact ? Theme.hit : 34
                    onClicked: App.commitTagInput()
                    contentItem: Text {
                        text: parent.text
                        color: parent.enabled ? Theme.accent : Theme.secondary
                        font.pixelSize: 14
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    background: Rectangle {
                        radius: 8
                        color: parent.down ? Theme.elevated : "transparent"
                    }
                }
            }

            ListView {
                visible: App.suggestions.count > 0
                width: parent.width
                height: Math.min(180, App.suggestions.count * 36)
                model: App.suggestions
                clip: true
                delegate: ItemDelegate {
                    width: ListView.view.width
                    height: 36
                    onClicked: App.addTag(model.name)
                    contentItem: Row {
                        spacing: 8
                        Text {
                            text: model.name
                            color: model.typeColor
                            font.pixelSize: 14
                            height: 36
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            visible: model.postCount > 0
                            text: model.postCount
                            color: Theme.secondary
                            font.pixelSize: 12
                            height: 36
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            contentWidth: width
            contentHeight: tagsColumn.height + 20

            Column {
                id: tagsColumn
                width: parent.width
                spacing: 0

                Item {
                    width: parent.width
                    height: 40
                    Text {
                        text: "Selected Tags"
                        color: Theme.text
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                    }
                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        HitButton {
                            glyph: "close"
                            enabled: App.selectedTags.length > 0
                            onClicked: App.clearTags()
                        }
                        HitButton {
                            glyph: "save"
                            enabled: App.selectedTags.length > 0
                            onClicked: saveDialog.open()
                        }
                        HitButton {
                            glyph: "list"
                            onClicked: savedSets.open()
                        }
                    }
                }

                Flow {
                    width: parent.width - 28
                    x: 14
                    spacing: 7
                    topPadding: 8
                    bottomPadding: 12

                    Text {
                        visible: App.selectedTags.length === 0
                        text: "No tags selected"
                        color: Theme.secondary
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: App.selectedTags
                        delegate: TagChip {
                            chipText: modelData
                            style: "page"
                            tint: App.tagColor(modelData)
                            onClicked: App.removeTag(modelData)
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: 40
                    Text {
                        text: "Tags on this page"
                        color: Theme.text
                        font.pixelSize: 16
                        font.weight: Font.DemiBold
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                    }
                    Text {
                        visible: App.pageTags.count > 0
                        text: App.pageTags.count
                        color: Theme.secondary
                        font.pixelSize: 12
                        height: parent.height
                        verticalAlignment: Text.AlignVCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                    }
                }

                Column {
                    width: parent.width - 28
                    x: 14
                    topPadding: 4
                    bottomPadding: 16
                    spacing: 10

                    Text {
                        visible: App.pageTagGroups.length === 0
                        text: App.loading ? "Loading…" : "No tags yet"
                        color: Theme.secondary
                        font.pixelSize: 12
                    }

                    Repeater {
                        model: App.pageTagGroups
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
                                        count: modelData.postCount
                                        onClicked: App.addTag(modelData.name)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Dialog {
        id: saveDialog
        title: "Save Tag Set"
        modal: true
        standardButtons: Dialog.Save | Dialog.Cancel
        width: Math.min(420, root.width - 24)
        x: (root.width - width) / 2
        y: 80

        Column {
            width: parent.width
            spacing: 12
            TextField {
                width: parent.width
                placeholderText: "Set name"
                text: App.selectedTags.slice(0, 2).join(" ")
                id: nameField
            }
            CheckBox {
                id: personalBox
                text: "Add to Personal feed"
            }
        }

        onAccepted: App.saveCurrentSet(nameField.text, personalBox.checked)
    }

    Dialog {
        id: savedSets
        title: "Saved Tag Sets"
        modal: true
        width: Math.min(480, root.width - 16)
        height: Math.min(420, root.height - 40)
        x: (root.width - width) / 2
        y: 40
        standardButtons: Dialog.Close

        ListView {
            anchors.fill: parent
            model: App.savedSets
            clip: true
            delegate: ItemDelegate {
                width: ListView.view.width
                height: 64
                contentItem: RowLayout {
                    spacing: 8
                    Column {
                        Layout.fillWidth: true
                        Text {
                            text: model.name
                            color: Theme.text
                            font.pixelSize: 15
                            verticalAlignment: Text.AlignVCenter
                        }
                        Text {
                            text: model.joined
                            color: Theme.secondary
                            font.pixelSize: 12
                            elide: Text.ElideRight
                            width: parent.width
                        }
                    }
                    CompactCheck {
                        checked: model.inPersonal
                        onToggled: App.togglePersonalSet(index, checked)
                    }
                    HitButton {
                        glyph: "close"
                        onClicked: App.deleteSavedSet(index)
                    }
                }
                onClicked: {
                    App.applySavedSet(index)
                    savedSets.close()
                }
            }
        }
    }
}
