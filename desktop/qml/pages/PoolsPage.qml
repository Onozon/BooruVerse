import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import BooruVerse

Item {
    Column {
        anchors.fill: parent
        visible: !App.poolDetail

        RowLayout {
            id: searchRow
            width: parent.width
            height: App.compact ? Theme.hit + 8 : 44

            Item { width: 16; height: 1 }

            TextField {
                Layout.fillWidth: true
                Layout.preferredHeight: App.compact ? Theme.hit : 34
                placeholderText: "Search pools…"
                text: App.poolQuery
                onTextChanged: App.poolQuery = text
                onAccepted: App.searchPools()
            }

            Button {
                text: "Search"
                implicitHeight: App.compact ? Theme.hit : 34
                onClicked: App.searchPools()
                contentItem: Text {
                    text: parent.text
                    color: Theme.accent
                    font.pixelSize: 14
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                background: Rectangle { color: "transparent" }
            }

            Item {
                visible: App.compact
                Layout.preferredWidth: poolChrome.implicitWidth
                Layout.preferredHeight: 36
                SelectionChrome {
                    id: poolChrome
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            RefreshButton {
                visible: App.compact
                Layout.preferredWidth: visible ? implicitWidth : 0
                Layout.preferredHeight: implicitHeight
                onClicked: App.searchPools()
            }

            Item { width: App.compact ? 8 : 16; height: 1 }
        }

        ListView {
            id: poolList
            width: parent.width
            height: parent.height - searchRow.height
            model: App.pools
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            reuseItems: true
            pressDelay: Qt.platform.os === "android" ? 80 : 0
            cacheBuffer: Math.max(0, Math.round(height * 1.2))

            onContentYChanged: {
                if (contentY > contentHeight - height - 240)
                    App.loadMore()
            }

            delegate: ItemDelegate {
                id: poolRow
                required property int index
                required property var previewUrls
                required property string name
                required property string description
                required property string serverId
                required property string colorHex
                required property int postCount
                width: ListView.view.width
                implicitHeight: col.implicitHeight + 20
                onClicked: App.openPool(index)

                ListView.onPooled: {
                    for (let i = 0; i < previewRepeater.count; ++i) {
                        const wrap = previewRepeater.itemAt(i)
                        if (wrap && wrap.thumb)
                            wrap.thumb.pause()
                    }
                }
                ListView.onReused: {
                    for (let i = 0; i < previewRepeater.count; ++i) {
                        const wrap = previewRepeater.itemAt(i)
                        if (wrap && wrap.thumb)
                            wrap.thumb.resume()
                    }
                }

                contentItem: Column {
                    id: col
                    spacing: 8

                    Row {
                        spacing: 8
                        Rectangle {
                            visible: poolRow.colorHex.length > 0
                            width: 8
                            height: 8
                            radius: 4
                            color: poolRow.colorHex
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: poolRow.name
                            color: Theme.text
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                            width: poolList.width - 48
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Text {
                        visible: poolRow.description.length > 0
                        text: poolRow.description
                        color: Theme.secondary
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        width: poolList.width - 32
                        maximumLineCount: 1
                    }

                    Row {
                        spacing: 4
                        height: 64
                        Repeater {
                            id: previewRepeater
                            model: 6
                            delegate: Rectangle {
                                property alias thumb: poolThumb
                                width: (poolList.width - 32 - 20) / 6
                                height: 64
                                radius: 6
                                color: Theme.dark ? "#2C2C2E" : "#E5E5EA"
                                clip: true

                                LazyThumb {
                                    id: poolThumb
                                    anchors.fill: parent
                                    fillMode: Image.PreserveAspectCrop
                                    maxPx: 220
                                    remoteUrl: index < poolRow.previewUrls.length ? poolRow.previewUrls[index] : ""
                                    visible: status === Image.Ready
                                }
                            }
                        }
                    }

                    Text {
                        text: poolRow.postCount + " posts · " + poolRow.serverId
                        color: Theme.secondary
                        font.pixelSize: 12
                    }
                }
            }

            footer: Item {
                width: parent.width
                height: App.loading ? 48 : 0
                BusyIndicator {
                    anchors.centerIn: parent
                    running: App.loading
                    visible: App.loading
                }
            }

            EmptyState {
                visible: App.pools.count === 0 && !App.loading
                anchors.centerIn: parent
                titleText: "No Pools"
                message: App.statusText
                glyph: "empty"
            }
        }
    }

    Column {
        anchors.fill: parent
        visible: App.poolDetail

        PageHeader {
            width: parent.width
            showBack: true
            busy: App.loading
            onBackClicked: App.leavePool()
            onRefreshClicked: App.reload()
        }

        PostGrid {
            width: parent.width
            height: parent.height - 52
        }
    }
}
