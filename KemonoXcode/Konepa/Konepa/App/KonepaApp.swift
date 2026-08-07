import SwiftUI
import SwiftData

@main
struct KonepaApp: App {
    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
        }
    }
}

/// Opens SwiftData off the first frame so a large local catalog does not block launch UI.
private struct AppBootstrapView: View {
    @State private var container: ModelContainer?

    var body: some View {
        Group {
            if let container {
                RootView()
                    .modelContainer(container)
            } else {
                ProgressView("Starting…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task {
            guard container == nil else { return }
            let created = await Task.detached(priority: .userInitiated) {
                ModelContainerFactory.make()
            }.value
            container = created
        }
    }
}
