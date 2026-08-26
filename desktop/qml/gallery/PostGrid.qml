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
    // Keep enough pooled cells for viewport + modest overscan; never 1:1 with post count.
    readonly property real overscan: Math.max(height * 0.45, 320)
    readonly property int pageSize: 40
    readonly property int loadMoreLeadPosts: Math.max(1, Math.floor(pageSize / 2))
    readonly property int poolSize: Math.max(48, Math.min(160, Math.ceil((height + overscan * 2) / 72) * Math.max(App.layoutColumns, 1) + 16))

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
        Qt.callLater(syncPool)
    }

    function relayout() {
        if (!ancestorVisible() || innerWidth < 8)
            return
        App.prepareLayout(innerWidth)
        Qt.callLater(syncPool)
    }

    function maybeLoadMore() {
        if (!ancestorVisible() || !flick.visible || App.loading)
            return
        const count = App.posts.count
        if (count <= 0)
            return
        const triggerIndex = Math.max(0, count - root.loadMoreLeadPosts)
        if (flick.contentY + flick.height >= App.itemY(triggerIndex))
            App.loadMore()
    }

    function bindCell(cell, postIndex) {
        const post = App.posts.get(postIndex)
        cell.postIndex = postIndex
        cell.x = App.itemX(postIndex)
        cell.y = App.itemY(postIndex)
        cell.width = App.layoutColumnWidth
        cell.height = App.itemH(postIndex)
        cell.upgrade = root.upgrade
        cell.previewUrl = post.previewUrl || ""
        cell.sampleUrl = post.sampleUrl || ""
        cell.caption = (post.serverId || "") + " #" + (post.postId || "")
        cell.borderColor = post.borderColor || ""
        cell.favorited = !!post.favorited
        cell.selected = !!post.selected
        cell.duplicateCount = post.duplicateCount || 1
        cell.aspect = post.aspectRatio || 1
        cell.visible = true
        cell.resumeThumb()
    }

    function clearCell(cell) {
        if (!cell)
            return
        cell.pauseThumb()
        cell.postIndex = -1
        cell.visible = false
    }

    function refreshCellMeta(cell) {
        if (!cell || cell.postIndex < 0)
            return
        const post = App.posts.get(cell.postIndex)
        cell.favorited = !!post.favorited
        cell.selected = !!post.selected
        cell.borderColor = post.borderColor || ""
        cell.duplicateCount = post.duplicateCount || 1
    }

    function syncPool() {
        if (!ancestorVisible() || !flick.visible) {
            for (let i = 0; i < cells.count; ++i)
                clearCell(cells.itemAt(i))
            return
        }

        const top = flick.contentY - root.overscan
        const bottom = flick.contentY + flick.height + root.overscan
        const needed = App.indexesInYRange(top, bottom)
        const neededSet = {}
        for (let n = 0; n < needed.length; ++n)
            neededSet[needed[n]] = true

        const kept = {}
        const freeSlots = []
        for (let s = 0; s < cells.count; ++s) {
            const cell = cells.itemAt(s)
            if (!cell)
                continue
            const idx = cell.postIndex
            if (idx >= 0 && neededSet[idx]) {
                kept[idx] = s
                cell.x = App.itemX(idx)
                cell.y = App.itemY(idx)
                cell.width = App.layoutColumnWidth
                cell.height = App.itemH(idx)
                cell.upgrade = root.upgrade
                cell.resumeThumb()
            } else {
                clearCell(cell)
                freeSlots.push(s)
            }
        }

        for (let n = 0; n < needed.length; ++n) {
            const idx = needed[n]
            if (kept[idx] !== undefined)
                continue
            if (freeSlots.length === 0)
                break
            const slot = freeSlots.pop()
            bindCell(cells.itemAt(slot), idx)
        }

        maybeLoadMore()
    }

    onInnerWidthChanged: relayout()
    onPoolSizeChanged: Qt.callLater(syncPool)
    onVisibleChanged: {
        if (visible)
            Qt.callLater(relayout)
        else
            syncPool()
    }
    Component.onCompleted: Qt.callLater(relayout)

    Connections {
        target: App
        function onLayoutChanged() { Qt.callLater(root.syncPool) }
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
        function onDataChanged() {
            for (let i = 0; i < cells.count; ++i)
                root.refreshCellMeta(cells.itemAt(i))
        }
    }

    Timer {
        id: visibilityTimer
        interval: 32
        repeat: false
        onTriggered: root.syncPool()
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
        // Avoid retaining offscreen item textures in the flickable layer.
        pixelAligned: true

        Repeater {
            id: cells
            model: root.poolSize
            delegate: PostCell {
                property int postIndex: -1
                visible: false
                upgrade: root.upgrade
                onTapped: {
                    if (postIndex < 0)
                        return
                    root.currentIndex = postIndex
                    App.openViewer(postIndex)
                }
                onPeeked: if (postIndex >= 0) App.openPeek(postIndex)
                onSelectToggled: if (postIndex >= 0) App.toggleSelectedAt(postIndex)
                onFavoriteToggled: if (postIndex >= 0) App.toggleFavoriteAt(postIndex)
            }
        }

        onContentYChanged: {
            if (!root.ancestorVisible())
                return
            if (!restorePending)
                App.scrollOffset = contentY
            visibilityTimer.restart()
            root.maybeLoadMore()
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
