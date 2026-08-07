import SwiftUI
import SwiftData

struct FeedView: View {
    @Query(sort: \Post.publishedAt, order: .reverse) private var posts: [Post]
    @Query(sort: \Subscription.subscribedAt, order: .reverse) private var subscriptions: [Subscription]

    var body: some View {
        Group {
            if subscriptions.isEmpty {
                ContentUnavailableView(
                    "No Subscriptions",
                    systemImage: "person.2",
                    description: Text("Subscribe to authors to build your feed.")
                )
            } else if posts.isEmpty {
                ContentUnavailableView(
                    "Feed Is Empty",
                    systemImage: "tray",
                    description: Text("Sync posts from your subscribed authors.")
                )
            } else {
                List(posts) { post in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(post.title)
                            .font(.headline)
                        Text(post.publishedAt, format: .dateTime)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Feed")
    }
}

#Preview {
    NavigationStack {
        FeedView()
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
