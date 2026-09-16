import SwiftUI

/// Asset catalog names for the shared Remix icon set in `icons/`.
enum AppIcon {
    static let feed = "fire-line"
    static let browse = "search-line"
    static let pools = "book-marked-line"
    static let favorites = "star-line"
    static let favoritesFill = "star-fill"
    static let settings = "settings-4-line"
    static let sidebar = "side-bar-line"
    static let close = "close-large-line"
    static let add = "add-large-line"
    static let refresh = "reset-right-line"
    static let back = "arrow-left-line"
    static let forward = "arrow-right-line"
    static let photo = "image-line"
    static let posts = "gallery-view-2"
    static let tags = "hashtag"
    static let save = "download-line"
    static let download = "download-line"
    static let site = "external-link-line"
    static let key = "key-fill"
    static let check = "checkbox-circle-line"
    static let checkBlank = "checkbox-blank-circle-line"
    static let error = "error-warning-line"
    static let list = "list-view"
    static let personal = "bard-line"
    static let folder = "folder-image-line"
    static let empty = "zzz-line"
    static let columns = "expand-height-line"
    static let adaptive = "expand-width-line"
    static let volumeMute = "volume-mute-line"
    static let volumeUp = "volume-up-line"
    static let dice = "dice-line"
}

extension Label where Title == Text, Icon == Image {
    init(_ title: String, appIcon: String) {
        self.init {
            Text(title)
        }         icon: {
            Image(appIcon)
                .renderingMode(.template)
        }
    }
}

extension Image {
    func appGlyph(size: CGFloat) -> some View {
        renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
