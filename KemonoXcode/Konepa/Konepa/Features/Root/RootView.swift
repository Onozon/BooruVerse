import SwiftUI
import SwiftData

enum AppSection: String, CaseIterable, Identifiable {
    case feed = "Feed"
    case recent = "Recent"
    case subscriptions = "Subscriptions"
    case search = "Search"
    case offline = "Offline"
    case settings = "Settings"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .feed: "rectangle.stack"
        case .recent: "clock"
        case .subscriptions: "person.2"
        case .search: "magnifyingglass"
        case .offline: "arrow.down.circle"
        case .settings: "gearshape"
        }
    }
}

struct RootView: View {
    @State private var selection: AppSection? = .feed

    var body: some View {
        NavigationSplitView {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Konepa")
#if os(macOS)
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
#endif
        } detail: {
            NavigationStack {
                switch selection ?? .feed {
                case .feed:
                    FeedView()
                case .recent:
                    RecentView()
                case .subscriptions:
                    SubscriptionsView()
                case .search:
                    SearchView()
                case .offline:
                    OfflineView()
                case .settings:
                    SettingsView()
                }
            }
        }
    }
}

#Preview {
    RootView()
        .modelContainer(ModelContainerFactory.make(inMemory: true))
}
