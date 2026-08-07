import SwiftUI
import SwiftData

struct AuthorRowView: View {
    let author: Author
    let isSubscribed: Bool
    var onSubscribe: (() -> Void)?

    var body: some View {
        HStack(spacing: 12) {
            AuthorAvatarView(name: author.name, avatarURL: author.avatarURL)

            VStack(alignment: .leading, spacing: 4) {
                Text(author.name)
                    .font(.headline)
                Text("\(author.service) · \(author.authorId)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if isSubscribed {
                Label("Subscribed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
            } else if let onSubscribe {
                Button("Subscribe", action: onSubscribe)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
