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
        .task { await model.bootstrapIfNeeded() }
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
            List {
                ForEach(model.pools, id: \.globalID) { pool in
                    NavigationLink(value: pool) {
                        PoolRowView(
                            pool: pool,
                            previewURLs: model.previewURLs(for: pool),
                            serverColor: serverColor(for: pool)
                        )
                    }
                    .task { await model.loadMoreIfNeeded(currentPool: pool) }
                    .task { await model.loadPreviews(for: pool) }
                }

                if model.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.plain)
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
                        .lineLimit(2)
                }

                if !pool.description.isEmpty {
                    Text(pool.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            previewStrip

            Text("^[\(pool.postCount) post](inflect: true)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var previewStrip: some View {
        if previewURLs.isEmpty {
            HStack(spacing: 4) {
                ForEach(0..<visibleCount, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.gray.opacity(0.12))
                        .frame(maxWidth: .infinity)
                        .frame(height: thumbnailHeight)
                }
            }
            .redacted(reason: .placeholder)
        } else {
            HStack(spacing: 4) {
                ForEach(Array(previewURLs.prefix(visibleCount).enumerated()), id: \.offset) { _, url in
                    RemoteThumbnail(url: url, contentMode: .fill, maxPixelSize: 220)
                        .frame(maxWidth: .infinity)
                        .frame(height: thumbnailHeight)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
    }
}
