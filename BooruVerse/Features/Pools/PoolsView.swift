import SwiftUI

struct PoolsView: View {
    @State private var model: PoolsViewModel
    @Environment(ServerStore.self) private var serverStore

    init(sites: [any BooruSite & BooruBrowsing]) {
        _model = State(initialValue: PoolsViewModel(servers: sites))
    }

    private func serverColor(for pool: BooruPool) -> Color? {
        guard serverStore.enabledCount >= 2 else { return nil }
        return serverStore.color(for: pool.serverID)
    }

    var body: some View {
        @Bindable var model = model

        NavigationStack {
            content
                .navigationTitle("Pools")
                .navigationDestination(for: BooruPool.self) { pool in
                    if let site = model.site(for: pool) {
                        PoolDetailView(pool: pool, site: site)
                    }
                }
                .searchable(text: $model.searchText, prompt: "Search pools")
                .onSubmit(of: .search) {
                    Task { await model.search() }
                }
                .onChange(of: model.searchText) { _, newValue in
                    if newValue.isEmpty {
                        Task { await model.search() }
                    }
                }
        }
        .task {
            await model.bootstrapIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage = model.errorMessage, model.pools.isEmpty {
            ContentUnavailableView {
                Label("Couldn't Load Pools", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Retry") {
                    Task { await model.refresh() }
                }
            }
        } else if model.pools.isEmpty && model.isLoading {
            ProgressView("Loading pools…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.pools.isEmpty {
            ContentUnavailableView(
                "No Pools",
                systemImage: "rectangle.stack",
                description: Text("Try a different search.")
            )
        } else {
            // ScrollView + LazyVStack keeps NavigationLink rows stable on macOS.
            // List + GeometryReader thumbnails was collapsing into a bare preview grid
            // after cancelled/resumed preview tasks.
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.pools, id: \.globalID) { pool in
                        NavigationLink(value: pool) {
                            PoolRowView(
                                pool: pool,
                                previewURLs: model.previewURLs(for: pool),
                                serverColor: serverColor(for: pool)
                            )
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .task(id: "more-\(pool.globalID)") {
                            await model.loadMoreIfNeeded(currentPool: pool)
                        }
                        .task(id: "preview-\(pool.globalID)") {
                            await model.loadPreviews(for: pool)
                        }

                        Divider()
                            .padding(.leading, 16)
                    }

                    if model.isLoadingMore {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                }
            }
            .refreshable { await model.refresh() }
        }
    }
}

private struct PoolRowView: View {
    let pool: BooruPool
    let previewURLs: [URL]
    var serverColor: Color?

    private let thumbnailHeight: CGFloat = 64
    private let visibleCount = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let serverColor {
                        Circle()
                            .fill(serverColor)
                            .frame(width: 8, height: 8)
                    }
                    Text(pool.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if !pool.description.isEmpty {
                    Text(pool.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            previewStrip
                // Previews are decorative; taps must hit the NavigationLink row.
                .allowsHitTesting(false)

            Text("^[\(pool.postCount) post](inflect: true)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var previewStrip: some View {
        HStack(spacing: 4) {
            ForEach(0..<visibleCount, id: \.self) { index in
                let url = previewURLs.indices.contains(index) ? previewURLs[index] : nil
                PoolPreviewThumb(url: url, height: thumbnailHeight)
            }
        }
        .frame(height: thumbnailHeight)
    }
}

/// Fixed-size pool strip thumbnail. Avoids GeometryReader so List/LazyVStack rows
/// cannot expand into a full-screen preview grid after image loads.
private struct PoolPreviewThumb: View {
    let url: URL?
    let height: CGFloat

    @State private var image: Image?
    @State private var failed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.12))

            if let image {
                image
                    .resizable()
                    .scaledToFill()
            } else if failed {
                Image(systemName: "photo")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task(id: url?.absoluteString ?? "nil") {
            await load()
        }
    }

    private func load() async {
        failed = false
        guard let url else {
            image = nil
            return
        }

        if let cached = await RemoteImageLoaderBridge.cachedImage(for: url, maxPixelSize: 220) {
            image = cached.swiftUIImage
            return
        }

        if let loaded = await RemoteImageLoaderBridge.load(
            url: url,
            priority: .visible,
            maxPixelSize: 220
        ) {
            image = loaded.swiftUIImage
        } else if image == nil {
            failed = true
        }
    }
}
