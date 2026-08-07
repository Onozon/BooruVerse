import SwiftUI

@MainActor
@Observable
final class PostSearchModel {
    var query = ""
    var results: [KemonoPostResult] = []
    var isLoading = false
    var errorMessage: String?
    var hasSearched = false

    private var searchTask: Task<Void, Never>?

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func search() {
        searchTask?.cancel()
        searchTask = Task {
            await performSearch()
        }
    }

    private func performSearch() async {
        let client = KemonoAPIClient(configuration: .current)
        guard !trimmedQuery.isEmpty else {
            results = []
            errorMessage = nil
            hasSearched = false
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try Task.checkCancellation()
            results = try await client.searchPosts(query: trimmedQuery)
            try Task.checkCancellation()
            hasSearched = true
        } catch is CancellationError {
            return
        } catch {
            results = []
            hasSearched = true
            errorMessage = error.localizedDescription
        }
    }

    func resetIfQueryCleared() {
        if trimmedQuery.isEmpty {
            results = []
            errorMessage = nil
            hasSearched = false
        }
    }
}

struct PostSearchView: View {
    @State private var model = PostSearchModel()

    var body: some View {
        Group {
            if model.trimmedQuery.isEmpty {
                ContentUnavailableView(
                    "Search Posts",
                    systemImage: "text.magnifyingglass",
                    description: Text("Enter a keyword, then tap Search or press Return.")
                )
            } else if model.isLoading {
                ProgressView("Searching posts…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage = model.errorMessage {
                ContentUnavailableView(
                    "Search Failed",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if !model.hasSearched {
                ContentUnavailableView(
                    "Ready to Search",
                    systemImage: "magnifyingglass",
                    description: Text("Tap Search to query kemono.cr for \"\(model.trimmedQuery)\".")
                )
            } else if model.results.isEmpty {
                ContentUnavailableView(
                    "No Posts Found",
                    systemImage: "doc.questionmark",
                    description: Text("Try a different query.")
                )
            } else {
                List(model.results) { post in
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
                .overlay(alignment: .bottom) {
                    Text("\(model.results.count) result(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 8)
                }
            }
        }
        .navigationTitle("Posts")
        .searchable(text: $model.query, prompt: "Search posts")
        .searchActionToolbar(isEnabled: !model.trimmedQuery.isEmpty, isLoading: model.isLoading) {
            model.search()
        }
        .onSubmit(of: .search) {
            model.search()
        }
        .onChange(of: model.query) { _, _ in
            model.resetIfQueryCleared()
        }
    }
}

#Preview {
    NavigationStack {
        PostSearchView()
    }
}
