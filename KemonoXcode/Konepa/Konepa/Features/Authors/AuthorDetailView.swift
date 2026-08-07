import SwiftUI
import SwiftData

struct AuthorDetailView: View {
    @Bindable var author: Author
    @Environment(\.modelContext) private var modelContext
    @Query private var subscriptions: [Subscription]
    @Query private var posts: [Post]
    @State private var model = AuthorDetailModel()

    init(author: Author) {
        self.author = author
        let service = author.service
        let authorId = author.authorId
        _posts = Query(
            filter: #Predicate<Post> { post in
                post.service == service && post.authorId == authorId
            },
            sort: [SortDescriptor(\Post.publishedAt, order: .reverse)]
        )
    }

    private var isSubscribed: Bool {
        subscriptions.contains { $0.authorKey == author.key }
    }

    private var totalPages: Int {
        max(1, (posts.count + model.pageSize - 1) / model.pageSize)
    }

    private var pagePosts: [Post] {
        let start = model.currentPage * model.pageSize
        let end = min(start + model.pageSize, posts.count)
        guard start < end else { return [] }
        return Array(posts[start..<end])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                authorHeader

                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .padding(.horizontal)
                }

                postsSection
            }
            .padding(.vertical)
        }
        .navigationTitle(author.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .safeAreaInset(edge: .bottom) {
            if posts.count > model.pageSize {
                paginationBar
            }
        }
        .overlay {
            if model.isLoading && posts.isEmpty {
                ProgressView("Loading posts…")
                    .padding(24)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .refreshable {
            await reloadPosts()
        }
        .task(id: author.key) {
            AuthorRepository.recordRecentView(for: author, in: modelContext)
            try? modelContext.save()
            await model.loadPosts(for: author, in: modelContext)
        }
    }

    private var authorHeader: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 16) {
                AuthorAvatarView(name: author.name, avatarURL: author.avatarURL)
                    .frame(width: 72, height: 72)

                VStack(alignment: .leading, spacing: 6) {
                    Text(author.name)
                        .font(.title2.bold())
                    Text(author.service)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("ID \(author.authorId)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let updatedAt = author.updatedAt {
                        Text("Updated \(updatedAt, format: .dateTime)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 12) {
                if isSubscribed {
                    Label("Subscribed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                } else {
                    Button("Subscribe") {
                        AuthorRepository.subscribe(to: author, in: modelContext)
                        try? modelContext.save()
                    }
                    .buttonStyle(.bordered)
                }

                if let url = authorPageURL {
                    Link(destination: url) {
                        Label("Open on kemono.cr", systemImage: "safari")
                    }
                    .buttonStyle(.bordered)
                }

                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(.horizontal)
    }

    @ViewBuilder
    private var postsSection: some View {
        if posts.isEmpty && !model.isLoading {
            ContentUnavailableView(
                "No Posts",
                systemImage: "doc.text",
                description: Text(model.errorMessage ?? "This author has no posts yet.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else if !posts.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Posts")
                        .font(.headline)
                    Spacer()
                    Text("\(posts.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)

                PostCardsGrid(posts: pagePosts)
                    .padding(.horizontal)
            }
        }
    }

    private var paginationBar: some View {
        HStack {
            Button("Previous") {
                model.currentPage = max(model.currentPage - 1, 0)
            }
            .disabled(model.currentPage == 0)

            Spacer()

            Text("\(model.currentPage + 1) / \(totalPages)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Next") {
                model.currentPage = min(model.currentPage + 1, totalPages - 1)
            }
            .disabled(model.currentPage >= totalPages - 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var authorPageURL: URL? {
        URL(string: "\(AppSettings.baseURL.absoluteString)/\(author.service)/user/\(author.authorId)")
    }

    private func reloadPosts() async {
        await model.loadPosts(for: author, in: modelContext, force: true)
    }
}

#Preview {
    NavigationStack {
        AuthorDetailView(
            author: Author(
                service: "fanbox",
                authorId: "17332140",
                name: "abmayo"
            )
        )
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
