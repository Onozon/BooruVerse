import SwiftUI

enum PostGridMetrics {
    static let spacing: CGFloat = 12
    /// Minimum card width — grid adds columns until this is respected.
    static let minCardWidth: CGFloat = 132
}

struct PostCardView: View {
    let post: Post

    private static let thumbnailHeight: CGFloat = 140
    private static let titleHeight: CGFloat = 54

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PostThumbnailView(previewURL: post.previewURL, height: Self.thumbnailHeight)

            VStack(alignment: .leading, spacing: 4) {
                Text(post.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: Self.titleHeight, maxHeight: Self.titleHeight, alignment: .topLeading)

                Text(post.publishedAt, format: .dateTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(10)
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .fixedSize(horizontal: false, vertical: true)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}

struct PostCardsGrid: View {
    let posts: [Post]
    var spacing: CGFloat = PostGridMetrics.spacing

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    /// Slightly smaller minimum on regular width (iPad / macOS) → more columns.
    private var minColumnWidth: CGFloat {
        horizontalSizeClass == .regular ? 150 : PostGridMetrics.minCardWidth
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: minColumnWidth), spacing: spacing)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: spacing) {
            ForEach(posts) { post in
                NavigationLink {
                    PostDetailView(post: post)
                } label: {
                    PostCardView(post: post)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Wide") {
    ScrollView {
        PostCardsGrid(posts: [])
            .padding()
            .frame(width: 900)
    }
}

#Preview("Narrow") {
    ScrollView {
        PostCardsGrid(posts: [])
            .padding()
            .frame(width: 320)
    }
}
