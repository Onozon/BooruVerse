import SwiftUI

struct AuthorAvatarView: View {
    let name: String
    let avatarURL: String?

    var body: some View {
        Group {
            if let avatarURL, !avatarURL.isEmpty {
                KemonoRemoteImage(urlString: avatarURL, contentMode: .fill)
            } else {
                placeholder
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(Circle())
    }

    private var placeholder: some View {
        ZStack {
            Circle()
                .fill(.quaternary)
            Text(name.prefix(1).uppercased())
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}
