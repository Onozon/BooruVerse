import QtQuick
import QtQuick.Controls
import BooruVerse

Item {
    id: root
    property int currentIndex: 0
    property bool restorePending: true

    readonly property int pad: Theme.gridPadding
    readonly property int gap: Theme.gridSpacing
    readonly property real innerWidth: Math.max(0, width - pad * 2)
    readonly property bool upgrade: App.layoutColumns === 1
    readonly property real overscan: Math.max(height * 0.75, 480)

    function ancestorVisible() {
        for (var item = root; item; item = item.parent) {
            if (item.visible === false)
                return false
        }
        return true
    }

    function restoreScroll(y) {
        restorePending = true
        flick.contentY = Math.max(0, y)
        restorePending = false
        Qt.callLater(updateThumbVisibility)
    }

    function relayout() {
        if (!ancestorVisible() || innerWidth < 8)
            return
        App.prepareLayout(innerWidth)
        Qt.callLater(updateThumbVisibility)
    }

    function updateThumbVisibility() {
        if (!ancestorVisible() || !flick.visible) {
            for (let i = 0; i < cells.count; ++i) {
                const cell = cells.itemAt(i)
                if (cell)
                    cell.pauseThumb()
            }
            return
        }
        const top = flick.contentY - root.overscan
        const bottom = flick.contentY + flick.height + root.overscan
        for (let i = 0; i < cells.count; ++i) {
            const cell = cells.itemAt(i)
            if (!cell)
                continue
            const onScreen = cell.y + cell.height >= top && cell.y <= bottom
            if (onScreen)
                cell.resumeThumb()
            else
                cell.pauseThumb()
        }
    }

    onInnerWidthChanged: relayout()
    onVisibleChanged: {
        if (visible)
            Qt.callLater(relayout)
        else
            updateThumbVisibility()
    }
    Component.onCompleted: Qt.callLater(relayout)

    Connections {
        target: App
        function onLayoutChanged() { Qt.callLater(root.updateThumbVisibility) }
        function onSettingsChanged() { Qt.callLater(root.relayout) }
        function onTabChanged() { Qt.callLater(root.relayout) }
        function onCompactChanged() { Qt.callLater(root.relayout) }
    }
    Connections {
        target: App.posts
        function onCountChanged() {
            root.relayout()
            visibilityTimer.restart()
        }
    }

    Timer {
        id: visibilityTimer
        interval: 48
        repeat: false
        onTriggered: root.updateThumbVisibility()
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.leftMargin: pad
        anchors.rightMargin: pad
        anchors.topMargin: pad
        anchors.bottomMargin: pad
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: Math.max(height, App.layoutHeight)
        visible: App.posts.count > 0
        focus: true
        pressDelay: Qt.platform.os === "android" ? 80 : 0

        Repeater {
            id: cells
            model: App.posts
            delegate: PostCell {
                id: cell
                x: App.itemX(index) + App.layoutHeight * 0
                y: App.itemY(index) + App.layoutHeight * 0
                width: App.layoutColumnWidth
                height: App.itemH(index) + App.layoutHeight * 0
                upgrade: root.upgrade
                previewUrl: model.previewUrl
                sampleUrl: model.sampleUrl
                caption: model.serverId + " #" + model.postId
                borderColor: model.borderColor
                favorited: model.favorited
                selected: model.selected
                duplicateCount: model.duplicateCount
                aspect: model.aspectRatio
                Component.onCompleted: visibilityTimer.restart()
                onTapped: {
                    root.currentIndex = index
                    App.openViewer(index)
                }
                onPeeked: App.openPeek(index)
                onSelectToggled: App.toggleSelectedAt(index)
                onFavoriteToggled: App.toggleFavoriteAt(index)
            }
        }

        onContentYChanged: {
            if (!root.ancestorVisible())
                return
            if (!restorePending)
                App.scrollOffset = contentY
            visibilityTimer.restart()
            if (contentHeight > 0 && contentY > contentHeight - height - 480)
                App.loadMore()
        }
        onHeightChanged: visibilityTimer.restart()
        onWidthChanged: visibilityTimer.restart()

        WheelHandler {
            acceptedModifiers: Qt.ControlModifier
            onWheel: function (event) {
                if (!root.ancestorVisible())
                    return
                App.tileExtent = App.tileExtent + (event.angleDelta.y > 0 ? 28 : -28)
                event.accepted = true
            }
        }

        PinchHandler {
            target: null
            property int baseExtent: 160
            onActiveChanged: {
                if (active)
                    baseExtent = App.tileExtent
            }
            onScaleChanged: {
                if (active && root.ancestorVisible())
                    App.tileExtent = Math.round(baseExtent * scale)
            }
        }

        Component.onCompleted: {
            if (App.scrollOffset > 0)
                Qt.callLater(function () { root.restoreScroll(App.scrollOffset) })
            else
                visibilityTimer.restart()
        }

        Keys.onPressed: function (event) {
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Up)
                root.currentIndex = Math.max(0, root.currentIndex - (event.key === Qt.Key_Up ? Math.max(App.layoutColumns, 1) : 1))
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down)
                root.currentIndex = Math.min(App.posts.count - 1, root.currentIndex + (event.key === Qt.Key_Down ? Math.max(App.layoutColumns, 1) : 1))
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                App.openViewer(root.currentIndex)
            else if (event.key === Qt.Key_F)
                App.toggleFavoriteAt(root.currentIndex)
            else
                return
            event.accepted = true
            flick.contentY = Math.max(0, App.itemY(root.currentIndex) - 40)
            visibilityTimer.restart()
        }
    }

    BusyIndicator {
        visible: App.posts.count === 0 && App.loading
        running: visible
        anchors.centerIn: parent
    }

    EmptyState {
        visible: App.posts.count === 0 && !App.loading && !App.personalEmpty
        titleText: "No Posts"
        message: App.errorText.length ? App.errorText : "Nothing matched this query."
        glyph: App.errorText.length ? "error" : "empty"
        anchors.centerIn: parent
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 180 } }
    }
}
