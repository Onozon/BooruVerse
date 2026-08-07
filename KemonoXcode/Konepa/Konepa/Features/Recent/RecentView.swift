import SwiftUI
import SwiftData

enum RecentTab: String, CaseIterable, Identifiable {
    case authors = "Authors"
    case posts = "Posts"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .authors: "person.crop.circle"
        case .posts: "doc.text"
        }
    }
}

struct RecentView: View {
    @State private var selectedTab: RecentTab = .authors
    @Query(sort: \RecentAuthor.lastViewedAt, order: .reverse) private var recentAuthors: [RecentAuthor]
    @Query(sort: \RecentPost.lastViewedAt, order: .reverse) private var recentPosts: [RecentPost]
    @Environment(\.modelContext) private var modelContext
    @Query private var subscriptions: [Subscription]

    private var subscribedKeys: Set<String> {
        Set(subscriptions.map(\.authorKey))
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Recent Type", selection: $selectedTab) {
                ForEach(RecentTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                switch selectedTab {
                case .authors:
                    recentAuthorsList
                case .posts:
                    recentPostsList
                }
            }
        }
        .navigationTitle("Recent")
    }

    @ViewBuilder
    private var recentAuthorsList: some View {
        if recentAuthors.isEmpty {
            ContentUnavailableView(
                "No Recent Authors",
                systemImage: "clock",
                description: Text("Authors you open will appear here.")
            )
        } else {
            List(recentAuthors) { entry in
                if let author = entry.author {
                    NavigationLink {
                        AuthorDetailView(author: author)
                    } label: {
                        HStack(spacing: 12) {
                            AuthorRowView(
                                author: author,
                                isSubscribed: subscribedKeys.contains(author.key),
                                onSubscribe: {
                                    AuthorRepository.subscribe(to: author, in: modelContext)
                                    try? modelContext.save()
                                }
                            )

                            Text(entry.lastViewedAt, format: .relative(presentation: .named))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(entry.authorKey)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var recentPostsList: some View {
        if recentPosts.isEmpty {
            ContentUnavailableView(
                "No Recent Posts",
                systemImage: "doc.text",
                description: Text("Posts you open will appear here.")
            )
        } else {
            List(recentPosts) { entry in
                if let post = entry.post {
                    NavigationLink {
                        PostDetailView(post: post)
                    } label: {
                        HStack(spacing: 12) {
                            PostThumbnailView(previewURL: post.previewURL, height: 56)
                                .frame(width: 72, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(post.title)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(post.publishedAt, format: .dateTime)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)

                            Text(entry.lastViewedAt, format: .relative(presentation: .named))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(entry.postKey)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        RecentView()
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
