import QtQuick
import BooruVerse

Item {
    id: root
    property string name: "dot"
    property color color: Theme.text
    implicitWidth: 22
    implicitHeight: 22

    readonly property string iconFile: {
        switch (root.name) {
        case "feed": return "fire-line.svg"
        case "browse":
        case "search": return "search-line.svg"
        case "pools": return "book-marked-line.svg"
        case "favorites": return "star-line.svg"
        case "favoritesFill": return "star-fill.svg"
        case "settings": return "settings-4-line.svg"
        case "sidebar": return "side-bar-line.svg"
        case "refresh": return "reset-right-line.svg"
        case "check":
        case "checkCircle": return "checkbox-circle-line.svg"
        case "checkBlank": return "checkbox-blank-circle-line.svg"
        case "tags": return "hashtag.svg"
        case "close": return "close-large-line.svg"
        case "chevronLeft": return "arrow-left-line.svg"
        case "chevronRight": return "arrow-right-line.svg"
        case "plus": return "add-large-line.svg"
        case "save":
        case "download": return "download-line.svg"
        case "site": return "external-link-line.svg"
        case "photo": return "image-line.svg"
        case "posts": return "gallery-view-2.svg"
        case "personal": return "bard-line.svg"
        case "key": return "key-fill.svg"
        case "folder": return "folder-image-line.svg"
        case "list": return "list-view.svg"
        case "error": return "error-warning-line.svg"
        case "empty": return "zzz-line.svg"
        case "columns": return "expand-height-line.svg"
        case "adaptive": return "expand-width-line.svg"
        default: return ""
        }
    }

    function hexColor(c) {
        function h(n) {
            return ("0" + Math.round(n * 255).toString(16)).slice(-2)
        }
        // Qt QColor 8-digit form is AARRGGBB, not RRGGBBAA.
        return h(c.a) + h(c.r) + h(c.g) + h(c.b)
    }

    Image {
        anchors.fill: parent
        visible: root.iconFile.length > 0
        fillMode: Image.PreserveAspectFit
        smooth: true
        asynchronous: false
        sourceSize.width: Math.ceil(Math.max(width, 1) * Screen.devicePixelRatio)
        sourceSize.height: Math.ceil(Math.max(height, 1) * Screen.devicePixelRatio)
        source: root.iconFile.length
                ? "image://uiicons/" + root.iconFile + "/" + root.hexColor(root.color)
                : ""
    }
}
