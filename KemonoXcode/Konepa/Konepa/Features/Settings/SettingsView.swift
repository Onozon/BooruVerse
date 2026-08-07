import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var catalogStates: [CatalogSyncState]

    @State private var baseURLString = AppSettings.baseURL.absoluteString
    @State private var sessionCookie = AppSettings.sessionCookie ?? ""
    @State private var didSave = false
    @State private var testMessage: String?
    @State private var isTesting = false
    @State private var syncEngine: CatalogSyncEngine?
    @State private var authorCount = 0

    private var catalogState: CatalogSyncState? {
        catalogStates.first
    }

    var body: some View {
        Form {
            Section {
                Picker("Mirror", selection: $baseURLString) {
                    ForEach(AppSettings.mirrorCandidates, id: \.absoluteString) { url in
                        Text(url.host ?? url.absoluteString).tag(url.absoluteString)
                    }
                }
                .onChange(of: baseURLString) { _, _ in
                    didSave = false
                }

                TextField("Session cookie (optional)", text: $sessionCookie, axis: .vertical)
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
#endif
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(2...4)
                    .onChange(of: sessionCookie) { _, _ in
                        didSave = false
                    }

                if baseURLString != AppSettings.defaultBaseURL.absoluteString {
                    Label("Mirror is not kemono.cr — use the same host as Safari", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                if AppSettings.hasSessionCookie {
                    Label("Cookie saved (\(AppSettings.sessionCookieLength) chars)", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("No cookie saved", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Button("Save Network Settings") {
                    saveSettings()
                }

                Button(isTesting ? "Testing…" : "Test Connection") {
                    testConnection()
                }
                .disabled(isTesting)

                if didSave {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                }

                if let testMessage {
                    Text(testMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Network")
            } footer: {
                Text("Use kemono.cr — the same host as Safari. Save session cookie before sync and search.")
            }

            Section {
                LabeledContent("Authors in database", value: "\(displayAuthorCount)")

                if let lastSyncedAt = catalogState?.lastSyncedAt {
                    LabeledContent("Last catalog sync") {
                        Text(lastSyncedAt, format: .relative(presentation: .named))
                    }
                } else {
                    LabeledContent("Last catalog sync", value: "Never")
                }

                if let syncEngine {
                    if syncEngine.isSyncing {
                        HStack {
                            ProgressView()
                            VStack(alignment: .leading, spacing: 4) {
                                switch syncEngine.phase {
                                case .downloading:
                                    Text("Downloading catalog…")
                                    Text("Connecting to server")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                case .importing:
                                    Text("Saving to database…")
                                    if syncEngine.downloadedCount > 0 {
                                        Text("\(syncEngine.savedCount) of \(syncEngine.downloadedCount) authors")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                case .idle:
                                    Text("Syncing…")
                                }
                                if syncEngine.attempt > 1 {
                                    Text("Retry attempt \(syncEngine.attempt)/\(CatalogSyncEngine.maxAttempts)")
                                        .font(.caption2)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                    } else {
                        Button("Sync Author Catalog") {
                            Task { await syncEngine.syncCatalog() }
                        }
                    }
                }

                if let error = catalogState?.lastError ?? syncEngine?.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Author Catalog")
            } footer: {
                Text("Downloads the creator list for local author search. Does not load the catalog in the UI.")
            }

            Section("About") {
                LabeledContent("Version", value: "1.0")
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear {
            let saved = AppSettings.baseURL
            if saved.host == "kemono.su" {
                baseURLString = AppSettings.defaultBaseURL.absoluteString
                testMessage = "kemono.su is unreliable — switched to kemono.cr. Tap Save."
            } else {
                baseURLString = saved.absoluteString
            }
            sessionCookie = AppSettings.sessionCookie ?? ""
            refreshCatalogInfo()
            if syncEngine == nil {
                syncEngine = CatalogSyncEngine(
                    modelContainer: modelContext.container,
                    mainContext: modelContext
                )
            }
        }
        .onChange(of: syncEngine?.isSyncing) { _, isSyncing in
            if isSyncing == false {
                refreshCatalogInfo()
            }
        }
    }

    private var displayAuthorCount: Int {
        if let syncEngine, syncEngine.isSyncing {
            return syncEngine.savedCount
        }
        return catalogState?.authorCount ?? authorCount
    }

    private func refreshCatalogInfo() {
        authorCount = (try? AuthorRepository.count(in: modelContext)) ?? 0
    }

    private func saveSettings() {
        AppSettings.baseURL = URL(string: baseURLString) ?? AppSettings.defaultBaseURL
        AppSettings.sessionCookie = sessionCookie
        sessionCookie = AppSettings.sessionCookie ?? ""
        didSave = true
        testMessage = nil
    }

    private func testConnection() {
        saveSettings()
        isTesting = true
        testMessage = nil

        Task {
            defer { isTesting = false }
            do {
                let client = KemonoAPIClient(configuration: .current)
                testMessage = try await client.testConnection()
            } catch {
                testMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
    .modelContainer(ModelContainerFactory.make(inMemory: true))
}
