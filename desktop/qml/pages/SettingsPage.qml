import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import BooruVerse

Item {
    id: root

    StackView {
        id: stack
        anchors.fill: parent
        initialItem: homePage
    }

    Component {
        id: homePage
        Flickable {
            clip: true
            contentWidth: width
            contentHeight: form.height + 32
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: form
                width: Math.min(parent.width - 32, App.compact ? parent.width - 32 : 720)
                x: (parent.width - width) / 2
                y: App.compact ? 8 : 16
                spacing: 18

                SettingsCard {
                    title: "Servers"
                    footer: "Enable one or more servers. Posts from every enabled server are combined into one feed."
                    width: parent.width

                    Repeater {
                        model: App.servers
                        delegate: ItemDelegate {
                            width: parent.width
                            implicitHeight: 52
                            onClicked: stack.push(serverPage, { serverIndex: index })

                            contentItem: RowLayout {
                                spacing: 10
                                CompactCheck {
                                    checked: model.enabled
                                    onToggled: App.setServerEnabled(index, checked)
                                }
                                Rectangle {
                                    width: 10
                                    height: 10
                                    radius: 5
                                    color: model.colorHex
                                    opacity: model.enabled ? 1 : 0.35
                                }
                                Column {
                                    Layout.fillWidth: true
                                    Text {
                                        text: model.host
                                        color: Theme.text
                                        font.pixelSize: 15
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    Text {
                                        text: model.flavorTitle + (model.builtIn ? " · Built-in" : "")
                                        color: Theme.secondary
                                        font.pixelSize: 12
                                    }
                                }
                                Glyph {
                                    visible: model.showKey
                                    name: "key"
                                    color: model.keyDanger ? Theme.danger : Theme.secondary
                                    width: 14
                                    height: 14
                                }
                                Glyph {
                                    name: "chevronRight"
                                    color: Theme.secondary
                                    width: 14
                                    height: 14
                                }
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        spacing: 8
                        TextField {
                            Layout.fillWidth: true
                            Layout.preferredHeight: App.compact ? Theme.hit : 34
                            placeholderText: "Add host, e.g. danbooru.donmai.us"
                            text: App.addHost
                            onTextChanged: App.addHost = text
                            onAccepted: App.addServer()
                        }
                        Button {
                            text: "Add"
                            implicitHeight: App.compact ? Theme.hit : 34
                            onClicked: App.addServer()
                            contentItem: Text {
                                text: parent.text
                                color: Theme.accent
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { color: "transparent" }
                        }
                    }

                    Text {
                        visible: App.addStatus.length > 0
                        text: App.addStatus
                        color: Theme.secondary
                        font.pixelSize: 12
                        width: parent.width
                        wrapMode: Text.WordWrap
                    }
                }

                SettingsCard {
                    title: "Feed"
                    footer: "Choose which saved tag sets appear in the Personal segment of Feed."
                    width: parent.width

                    ItemDelegate {
                        width: parent.width
                        implicitHeight: 48
                        padding: 0
                        leftPadding: 0
                        rightPadding: 0
                        onClicked: stack.push(personalPage)
                        contentItem: Row {
                            spacing: 10
                            Glyph {
                                name: "personal"
                                color: Theme.text
                                width: 18
                                height: 18
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "Personal Feed"
                                color: Theme.text
                                font.pixelSize: 15
                                width: parent.width - 18 - 10 - 14 - 10
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                            }
                            Glyph {
                                name: "chevronRight"
                                color: Theme.secondary
                                width: 14
                                height: 14
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                }

                SettingsCard {
                    title: "Content Rating"
                    footer: "Applies everywhere (Browse, Feed, Pools, Favorites)."
                    width: parent.width

                    Repeater {
                        model: [
                            { title: "All ratings", desc: "Show every post." },
                            { title: "Hide explicit", desc: "Safe, sensitive, and questionable remain visible." },
                            { title: "Safe only", desc: "Only posts marked safe / general." }
                        ]
                        delegate: ItemDelegate {
                            width: parent.width
                            implicitHeight: 58
                            padding: 0
                            leftPadding: 0
                            rightPadding: 0
                            onClicked: App.ratingFilter = index
                            contentItem: Item {
                                implicitHeight: 58
                                Row {
                                    anchors.fill: parent
                                    spacing: 10
                                    Column {
                                        width: parent.width - 28
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text { text: modelData.title; color: Theme.text; font.pixelSize: 15 }
                                        Text {
                                            text: modelData.desc
                                            color: Theme.secondary
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            width: parent.width
                                        }
                                    }
                                    Item {
                                        width: 18
                                        height: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                        Glyph {
                                            anchors.fill: parent
                                            visible: App.ratingFilter === index
                                            name: "check"
                                            color: Theme.text
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                SettingsCard {
                    title: "Gallery"
                    footer: "Layout applies to Browse, Feed, Favorites, and Pools. Full quality downloads the original file when a post opens."
                    width: parent.width

                    Repeater {
                        model: [
                            { title: "Columns", desc: "Fixed column width with independent vertical stacks, like Pinterest." },
                            { title: "Adaptive Rows", desc: "Equal column width with a shared row height." }
                        ]
                        delegate: ItemDelegate {
                            width: parent.width
                            implicitHeight: 58
                            padding: 0
                            leftPadding: 0
                            rightPadding: 0
                            onClicked: App.tilingMode = index
                            contentItem: Item {
                                implicitHeight: 58
                                Row {
                                    anchors.fill: parent
                                    spacing: 10
                                    Glyph {
                                        name: index === 0 ? "columns" : "adaptive"
                                        color: Theme.text
                                        width: 18
                                        height: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Column {
                                        width: parent.width - 18 - 10 - 18 - 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2
                                        Text { text: modelData.title; color: Theme.text; font.pixelSize: 15 }
                                        Text {
                                            text: modelData.desc
                                            color: Theme.secondary
                                            font.pixelSize: 12
                                            wrapMode: Text.WordWrap
                                            width: parent.width
                                        }
                                    }
                                    Item {
                                        width: 18
                                        height: 18
                                        anchors.verticalCenter: parent.verticalCenter
                                        Glyph {
                                            anchors.fill: parent
                                            visible: App.tilingMode === index
                                            name: "check"
                                            color: Theme.text
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        height: 32
                        Text {
                            text: "Thumbnail size"
                            color: Theme.text
                            font.pixelSize: 15
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                        }
                        Slider {
                            from: 72
                            to: 360
                            stepSize: 28
                            value: App.tileExtent
                            onMoved: App.tileExtent = value
                            Layout.preferredWidth: 140
                        }
                    }

                    RowLayout {
                        width: parent.width
                        height: 32
                        Text {
                            text: "Load full quality in viewer"
                            color: Theme.text
                            font.pixelSize: 15
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            verticalAlignment: Text.AlignVCenter
                        }
                        CompactSwitch {
                            checked: App.loadFullQuality
                            onToggled: App.loadFullQuality = checked
                        }
                    }
                }

                SettingsCard {
                    title: "Downloads"
                    footer: "Selected posts download into this folder. Turn on Ask every time to pick a folder for each batch."
                    width: parent.width

                    RowLayout {
                        width: parent.width
                        Text {
                            text: App.downloadFolder
                            color: Theme.text
                            font.pixelSize: 14
                            elide: Text.ElideMiddle
                            Layout.fillWidth: true
                            wrapMode: Text.NoWrap
                        }
                        Button {
                            text: "Choose…"
                            implicitHeight: App.compact ? Theme.hit : 34
                            onClicked: downloadFolderDialog.open()
                            contentItem: Text {
                                text: parent.text
                                color: Theme.accent
                                font.pixelSize: 14
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                            background: Rectangle { color: "transparent" }
                        }
                    }

                    RowLayout {
                        width: parent.width
                        height: 32
                        Text {
                            text: "Ask every time"
                            color: Theme.text
                            font.pixelSize: 15
                            Layout.fillWidth: true
                            verticalAlignment: Text.AlignVCenter
                        }
                        CompactSwitch {
                            checked: App.askDownloadFolder
                            onToggled: App.askDownloadFolder = checked
                        }
                    }
                }
            }
        }
    }

    Component {
        id: serverPage
        Flickable {
            property int serverIndex: 0
            property var info: App.servers.serverAt(serverIndex)
            clip: true
            contentWidth: width
            contentHeight: body.height + 32

            Connections {
                target: App.servers
                function onCountChanged() { info = App.servers.serverAt(serverIndex) }
            }
            Connections {
                target: App
                function onSettingsChanged() { info = App.servers.serverAt(serverIndex) }
            }

            Column {
                id: body
                width: Math.min(parent.width - 32, 640)
                x: (parent.width - width) / 2
                y: 8
                spacing: 16

                PageHeader {
                    width: parent.width
                    showBack: true
                    showRefresh: false
                    onBackClicked: stack.pop()
                }

                SettingsCard {
                    title: info.host || "Server"
                    footer: "Border color outlines posts from this server when two or more servers are enabled."
                    width: parent.width

                    Text {
                        text: (info.flavorTitle || "") + (info.builtIn ? " · Built-in" : "")
                        color: Theme.secondary
                        font.pixelSize: 13
                    }

                    TextField {
                        visible: info.flavor === 1 || info.flavor === 2
                        width: parent.width
                        placeholderText: info.credentialTitle || "User ID"
                        text: info.userId || ""
                        onEditingFinished: App.setServerCredentials(serverIndex, text, keyField.text)
                    }
                    TextField {
                        id: keyField
                        visible: info.flavor === 1 || info.flavor === 2
                        width: parent.width
                        placeholderText: "API key"
                        echoMode: TextInput.Password
                        text: info.apiKey || ""
                        onEditingFinished: App.setServerCredentials(serverIndex, info.userId || "", text)
                    }

                    Text {
                        text: "Border Color"
                        color: Theme.secondary
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        height: 20
                        verticalAlignment: Text.AlignVCenter
                    }

                    Flow {
                        width: parent.width
                        spacing: 10
                        Repeater {
                            model: App.serverPalette
                            delegate: Item {
                                width: 32
                                height: 32
                                readonly property bool selected: String(modelData).toLowerCase() === String(info.colorHex).toLowerCase()
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 16
                                    color: modelData
                                    Glyph {
                                        visible: selected
                                        name: "check"
                                        color: "white"
                                        anchors.fill: parent
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        App.setServerColor(serverIndex, modelData)
                                        info = App.servers.serverAt(serverIndex)
                                    }
                                }
                            }
                        }
                    }

                    HitButton {
                        visible: !info.builtIn
                        glyph: "close"
                        text: "Remove Server"
                        glyphColor: Theme.danger
                        onClicked: {
                            App.removeServer(serverIndex)
                            stack.pop()
                        }
                    }
                }
            }
        }
    }

    Component {
        id: personalPage
        Flickable {
            clip: true
            contentWidth: width
            contentHeight: personalBody.height + 32

            Column {
                id: personalBody
                width: Math.min(parent.width - 32, 640)
                x: (parent.width - width) / 2
                y: 8
                spacing: 16

                PageHeader {
                    width: parent.width
                    showBack: true
                    showRefresh: false
                    onBackClicked: stack.pop()
                }

                SettingsCard {
                    title: "Personal Feed"
                    footer: "Checked sets are mixed into the Personal segment of Feed."
                    width: parent.width

                    Repeater {
                        model: App.savedSets
                        delegate: RowLayout {
                            width: parent.width
                            height: 48
                            CompactCheck {
                                checked: model.inPersonal
                                onToggled: App.togglePersonalSet(index, checked)
                            }
                            Column {
                                Layout.fillWidth: true
                                Text { text: model.name; color: Theme.text; font.pixelSize: 15 }
                                Text {
                                    text: model.joined
                                    color: Theme.secondary
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                    width: parent.width
                                }
                            }
                        }
                    }

                    EmptyState {
                        visible: App.savedSets.count === 0
                        titleText: "No Saved Tag Sets"
                        message: "Save a tag set from Browse to use it here."
                        glyph: "empty"
                    }
                }
            }
        }
    }

    component SettingsCard: Column {
        id: card
        property string title: ""
        property string footer: ""
        default property alias content: cardBody.data
        spacing: 8

        Text {
            text: card.title
            color: Theme.secondary
            font.pixelSize: 13
            font.weight: Font.DemiBold
            leftPadding: 4
            height: 18
            verticalAlignment: Text.AlignVCenter
        }

        Rectangle {
            width: parent.width
            implicitHeight: cardBody.height + 20
            radius: 12
            color: Theme.surface
            Column {
                id: cardBody
                x: 12
                y: 10
                width: parent.width - 24
                spacing: 8
            }
        }

        Text {
            text: card.footer
            color: Theme.secondary
            font.pixelSize: 12
            width: parent.width
            wrapMode: Text.WordWrap
            leftPadding: 4
        }
    }

    FolderDialog {
        id: downloadFolderDialog
        currentFolder: App.downloadFolder.length ? "file://" + App.downloadFolder : ""
        onAccepted: App.downloadFolder = selectedFolder.toString()
    }
}
