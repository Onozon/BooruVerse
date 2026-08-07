import SwiftUI
import SwiftData

struct SubscriptionsView: View {
    @Query(sort: \Subscription.subscribedAt, order: .reverse) private var subscriptions: [Subscription]

    var body: some View {
        Group {
            if subscriptions.isEmpty {
                ContentUnavailableView(
                    "No Subscriptions Yet",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Subscribe from Authors or Recent.")
                )
            } else {
                List(subscriptions) { subscription in
                    if let author = subscription.author {
                        NavigationLink {
                            AuthorDetailView(author: author)
                        } label: {
                            HStack(spacing: 12) {
                                AuthorAvatarView(name: author.name, avatarURL: author.avatarURL)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(author.name)
                                        .font(.headline)
                                    Text("\(author.service) · \(author.authorId)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    } else {
                        Text(subscription.authorKey)
                    }
                }
            }
        }
        .navigationTitle("Subscriptions")
    }
}

#Preview {
    NavigationStack {
        SubscriptionsView()
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
