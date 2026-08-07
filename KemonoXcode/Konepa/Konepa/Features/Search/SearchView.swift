import SwiftUI
import SwiftData

enum SearchTab: String, CaseIterable, Identifiable {
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

struct SearchView: View {
    @State private var selectedTab: SearchTab = .authors

    var body: some View {
        VStack(spacing: 0) {
            Picker("Search Type", selection: $selectedTab) {
                ForEach(SearchTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.systemImage)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                switch selectedTab {
                case .authors:
                    ArtistSearchView()
                case .posts:
                    PostSearchView()
                }
            }
        }
        .navigationTitle("Search")
    }
}

#Preview {
    NavigationStack {
        SearchView()
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
