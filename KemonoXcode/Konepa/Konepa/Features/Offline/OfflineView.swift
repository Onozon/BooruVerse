import SwiftUI
import SwiftData

enum OfflineTab: String, CaseIterable, Identifiable {
    case authors = "Authors"
    case posts = "Posts"
    case subscriptions = "Subscriptions"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .authors: "person.crop.circle"
        case .posts: "doc.text"
        case .subscriptions: "person.2"
        }
    }
}

struct OfflineView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedTab: OfflineTab = .posts
    @State private var cachedAuthors: [Author] = []
    @State private var cachedPosts: [Post] = []
    @State private var subscriptions: [Subscription] = []
    @State private var cachedAuthorCount = 0
    @State private var postCount = 0
    @State private var subscriptionCount = 0
    @State private var isLoading = false

    var body: some View {
        VStack(spacing: 0) {
            offlineSummary

            Picker("Offline Content", selection: $selectedTab) {
                ForEach(OfflineTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .bottom])

            Group {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    switch selectedTab {
                    case .authors:
                        offlineAuthorsList
                    case .posts:
                        offlinePostsList
                    case .subscriptions:
                        offlineSubscriptionsList
                    }
                }
            }
        }
        .navigationTitle("Offline")
        .task(id: selectedTab) {
            await reloadCurrentTab()
        }
    }

    private var offlineSummary: some View {
        HStack(spacing: 16) {
            summaryTile(title: "Cached Authors", value: cachedAuthorCount, systemImage: "person.crop.circle")
            summaryTile(title: "Posts", value: postCount, systemImage: "doc.text")
            summaryTile(title: "Subscriptions", value: subscriptionCount, systemImage: "person.2")
        }
        .padding()
    }

    private func summaryTile(title: String, value: Int, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: systemImage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.title2.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var offlineAuthorsList: some View {
        if cachedAuthors.isEmpty {
            ContentUnavailableView(
                "No Cached Authors",
                systemImage: "person.crop.circle.badge.minus",
                description: Text("Authors with downloaded posts will appear here.")
            )
        } else {
            List(cachedAuthors) { author in
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
                            if let syncState = author.syncState {
                                Text(syncState.isFullySynced ? "Fully synced" : "Partial sync")
                                    .font(.caption2)
                                    .foregroundStyle(syncState.isFullySynced ? .green : .orange)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    @ViewBuilder
    private var offlinePostsList: some View {
        if cachedPosts.isEmpty {
            ContentUnavailableView(
                "No Cached Posts",
                systemImage: "tray.full",
                description: Text("Synced post metadata will be stored for offline browsing.")
            )
        } else {
            List(cachedPosts) { post in
                VStack(alignment: .leading, spacing: 4) {
                    Text(post.title)
                        .font(.headline)
                        .lineLimit(2)
                    HStack(spacing: 8) {
                        Text(post.service)
                        Text("·")
                        Text(post.authorId)
                        Text("·")
                        Text(post.publishedAt, format: .dateTime)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
    }

    @ViewBuilder
    private var offlineSubscriptionsList: some View {
        if subscriptions.isEmpty {
            ContentUnavailableView(
                "No Subscriptions Cached",
                systemImage: "person.2",
                description: Text("Subscribe to authors to keep their data available offline.")
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
                                Text("Subscribed \(subscription.subscribedAt, format: .dateTime)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text(subscription.authorKey)
                }
            }
        }
    }

    @MainActor
    private func reloadCurrentTab() async {
        isLoading = true
        defer { isLoading = false }

        cachedAuthorCount = (try? AuthorRepository.offlineAuthorCount(in: modelContext)) ?? 0
        postCount = (try? AuthorRepository.countPosts(in: modelContext)) ?? 0
        subscriptionCount = (try? AuthorRepository.countSubscriptions(in: modelContext)) ?? 0

        switch selectedTab {
        case .authors:
            cachedAuthors = (try? AuthorRepository.fetchOfflineAuthors(in: modelContext)) ?? []
        case .posts:
            cachedPosts = (try? AuthorRepository.fetchRecentPosts(in: modelContext)) ?? []
        case .subscriptions:
            subscriptions = (try? AuthorRepository.fetchSubscriptions(in: modelContext)) ?? []
        }
    }
}

#Preview {
    NavigationStack {
        OfflineView()
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
