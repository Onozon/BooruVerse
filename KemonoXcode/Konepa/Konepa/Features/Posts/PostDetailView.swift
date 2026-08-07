import SwiftUI
import SwiftData

struct PostDetailView: View {
    @Bindable var post: Post
    @Environment(\.modelContext) private var modelContext
    @State private var model = PostDetailModel()
    @State private var selectedMedia: KemonoMediaItem?
    @State private var showDescription = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if let errorMessage = model.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }

                if model.isLoading && model.detail == nil {
                    ProgressView("Loading post…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 40)
                } else if let detail = model.detail {
                    if !detail.mediaItems.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Media")
                                .font(.headline)
                            PostMediaGrid(items: detail.mediaItems) { item in
                                selectedMedia = item
                            }
                        }
                    }

                    if showDescription, !detail.contentHTML.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.headline)
                            KemonoHTMLView(html: detail.contentHTML)
                        }
                    } else if !detail.contentHTML.isEmpty {
                        ProgressView("Loading description…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }

                    if detail.mediaItems.isEmpty && detail.contentHTML.isEmpty {
                        ContentUnavailableView(
                            "No Content",
                            systemImage: "doc.text",
                            description: Text("This post has no text or media.")
                        )
                    }
                } else if let errorMessage = model.errorMessage {
                    ContentUnavailableView(
                        "Failed to Load",
                        systemImage: "exclamationmark.triangle",
                        description: Text(errorMessage)
                    )
                    .padding(.top, 24)
                }
            }
            .padding()
        }
        .navigationTitle(post.title)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            if let url = model.detail?.pageURL ?? postPageURL {
                ToolbarItem(placement: .automatic) {
                    Link(destination: url) {
                        Label("Open on Site", systemImage: "safari")
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedMedia) { item in
            PostMediaViewer(item: item)
        }
        .refreshable {
            await model.load(post: post, in: modelContext)
        }
        .task(id: post.key) {
            showDescription = false
            await model.load(post: post, in: modelContext)
        }
        .onChange(of: model.detail?.postId) { _, _ in
            scheduleDescriptionReveal()
        }
    }

    private func scheduleDescriptionReveal() {
        showDescription = false
        Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            showDescription = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.title)
                .font(.title2.bold())

            HStack(spacing: 8) {
                Text(post.service)
                Text("·")
                Text(post.publishedAt, format: .dateTime)
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let author = post.author {
                NavigationLink {
                    AuthorDetailView(author: author)
                } label: {
                    Label(author.name, systemImage: "person.circle")
                }
                .font(.subheadline)
            }
        }
    }

    private var postPageURL: URL? {
        URL(string: "\(AppSettings.baseURL.absoluteString)/\(post.service)/user/\(post.authorId)/post/\(post.postId)")
    }
}

private struct PostMediaGrid: View {
    let items: [KemonoMediaItem]
    let onSelect: (KemonoMediaItem) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: PostGridMetrics.minCardWidth), spacing: PostGridMetrics.spacing)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: PostGridMetrics.spacing) {
            ForEach(items) { item in
                Button {
                    onSelect(item)
                } label: {
                    PostMediaTile(item: item)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct PostMediaTile: View {
    let item: KemonoMediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            mediaPreview
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(item.name)
                .font(.caption)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var mediaPreview: some View {
        if item.isImage {
            PostThumbnailView(previewURL: item.path, height: 140)
        } else if item.isVideo {
            ZStack {
                Color.gray.opacity(0.12)
                Image(systemName: "play.rectangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        } else {
            ZStack {
                Color.gray.opacity(0.12)
                Image(systemName: "doc.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PostMediaViewer: View {
    @Environment(\.dismiss) private var dismiss
    let item: KemonoMediaItem
    @State private var usedPreviewFallback = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if item.isImage {
                ZoomableRemoteImage(
                    path: item.path,
                    resolution: .full,
                    onPreviewFallback: { usedPreviewFallback = $0 }
                )
                .ignoresSafeArea()
            } else if let url = item.fullURL, let link = URL(string: url) {
                ContentUnavailableView(
                    item.name,
                    systemImage: item.isVideo ? "play.rectangle" : "doc",
                    description: Text("Open this file in Safari")
                )
                .overlay {
                    Link("Open File", destination: link)
                        .font(.headline)
                        .offset(y: 80)
                }
            }
        }
        .overlay(alignment: .top) {
            if usedPreviewFallback {
                Label(
                    "Full resolution unavailable — showing preview.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.35))
                    .padding()
            }
        }
        .statusBarHidden(true)
    }
}

#Preview {
    NavigationStack {
        PostDetailView(
            post: Post(
                service: "fanbox",
                authorId: "17332140",
                postId: "11484483",
                title: "Sample Post",
                publishedAt: .now
            )
        )
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
