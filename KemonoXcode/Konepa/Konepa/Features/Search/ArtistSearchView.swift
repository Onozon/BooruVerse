import SwiftUI
import SwiftData

@MainActor
@Observable
final class ArtistSearchModel {
    var query = ""
    var results: [Author] = []
    var isLoading = false
    var errorMessage: String?
    var hasSearched = false
    var catalogIsEmpty = false

    private var searchTask: Task<Void, Never>?

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func prepare(modelContext: ModelContext) {
        catalogIsEmpty = (try? AuthorRepository.count(in: modelContext)) == 0
    }

    func search(modelContext: ModelContext) {
        searchTask?.cancel()
        searchTask = Task {
            await performSearch(modelContext: modelContext)
        }
    }

    private func performSearch(modelContext: ModelContext) async {
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
            catalogIsEmpty = try AuthorRepository.count(in: modelContext) == 0
            if catalogIsEmpty {
                results = []
                hasSearched = true
                errorMessage = "Author catalog is empty. Sync it in Settings first."
                return
            }

            results = try AuthorRepository.search(query: trimmedQuery, in: modelContext)
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

struct ArtistSearchView: View {
    @State private var model = ArtistSearchModel()
    @Environment(\.modelContext) private var modelContext
    @Query private var subscriptions: [Subscription]

    private var subscribedKeys: Set<String> {
        Set(subscriptions.map(\.authorKey))
    }

    var body: some View {
        Group {
            if model.catalogIsEmpty {
                ContentUnavailableView(
                    "Catalog Not Synced",
                    systemImage: "arrow.triangle.2.circlepath",
                    description: Text("Sync the author catalog in Settings to search locally.")
                )
            } else if model.trimmedQuery.isEmpty {
                ContentUnavailableView(
                    "Search Authors",
                    systemImage: "magnifyingglass.circle",
                    description: Text("Search the local author catalog.")
                )
            } else if model.isLoading {
                ProgressView("Searching…")
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
                    description: Text("Tap Search to find \"\(model.trimmedQuery)\" in the local catalog.")
                )
            } else if model.results.isEmpty {
                ContentUnavailableView(
                    "No Authors Found",
                    systemImage: "person.fill.questionmark",
                    description: Text("Try a different query.")
                )
            } else {
                List(model.results) { author in
                    NavigationLink {
                        AuthorDetailView(author: author)
                    } label: {
                        HStack(spacing: 12) {
                            AuthorRowView(
                                author: author,
                                isSubscribed: subscribedKeys.contains(author.key),
                                onSubscribe: {
                                    subscribe(to: author)
                                }
                            )
                        }
                    }
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
        .navigationTitle("Authors")
        .searchable(text: $model.query, prompt: "Search authors")
        .searchActionToolbar(isEnabled: !model.trimmedQuery.isEmpty, isLoading: model.isLoading) {
            model.search(modelContext: modelContext)
        }
        .onSubmit(of: .search) {
            model.search(modelContext: modelContext)
        }
        .onChange(of: model.query) { _, _ in
            model.resetIfQueryCleared()
        }
        .onAppear {
            model.prepare(modelContext: modelContext)
        }
    }

    private func subscribe(to author: Author) {
        AuthorRepository.subscribe(to: author, in: modelContext)
        try? modelContext.save()
    }
}

#Preview {
    NavigationStack {
        ArtistSearchView()
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
