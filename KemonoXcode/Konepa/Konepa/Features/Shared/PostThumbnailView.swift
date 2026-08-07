import SwiftUI

struct PostThumbnailView: View {
    let previewURL: String?
    var height: CGFloat = 150

    var body: some View {
        KemonoRemoteImage(urlString: previewURL, contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(height: height)
            .clipped()
            .background(Color.gray.opacity(0.12))
            .contentShape(Rectangle())
    }
}
