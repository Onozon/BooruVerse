import QtQuick
import BooruVerse

Item {
    id: root
    property url remoteUrl
    property int maxPx: 480
    property int debounceMs: 56
    property bool paused: false
    property bool keepCached: false
    property alias fillMode: image.fillMode
    property alias smooth: image.smooth
    readonly property alias status: image.status

    function pause() {
        paused = true
        startTimer.stop()
        image.source = ""
    }

    function resume() {
        paused = false
        schedule()
    }

    function schedule() {
        startTimer.stop()
        if (paused || !isHttp(remoteUrl)) {
            image.source = ""
            return
        }
        startTimer.interval = debounceMs
        startTimer.start()
    }

    function isHttp(url) {
        const raw = String(url)
        return raw.startsWith("http://") || raw.startsWith("https://")
    }

    function providerSource(url, px) {
        return "image://thumbs/" + px + "/" + encodeURIComponent(String(url))
    }

    onRemoteUrlChanged: if (!paused) schedule()
    onMaxPxChanged: if (!paused) schedule()
    onPausedChanged: {
        if (paused) {
            startTimer.stop()
            image.source = ""
        } else {
            schedule()
        }
    }
    Component.onCompleted: if (!paused) schedule()

    Timer {
        id: startTimer
        interval: 56
        repeat: false
        onTriggered: {
            if (root.paused || !root.isHttp(root.remoteUrl)) {
                image.source = ""
                return
            }
            image.source = root.providerSource(root.remoteUrl, root.maxPx)
        }
    }

    Image {
        id: image
        anchors.fill: parent
        asynchronous: true
        // Grid thumbs must not pin every decoded pixmap in Qt's shared image cache.
        cache: root.keepCached
        sourceSize.width: root.maxPx
        sourceSize.height: root.maxPx
    }
}
