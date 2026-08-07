import SwiftUI

struct SettingsPlaceholderView: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ServerStore.self) private var servers

    @State private var showAddServer = false

    var body: some View {
        NavigationStack {
            Form {
                serversSection
                ratingSection
                gallerySection
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showAddServer) {
                AddServerView()
            }
        }
    }

    private var serversSection: some View {
        Section {
            ForEach(servers.servers) { server in
                ServerRow(server: server)
            }
            .onDelete(perform: deleteServers)

            Button {
                showAddServer = true
            } label: {
                Label("Add Server", systemImage: "plus.circle")
            }
        } header: {
            Text("Servers")
        } footer: {
            Text("Enable one or more servers. Posts from every enabled server are combined into one feed. At least one server must stay enabled.")
        }
    }

    private var ratingSection: some View {
        Section {
            ForEach(RatingFilter.allCases) { filter in
                Button {
                    settings.ratingFilter = filter
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(filter.title)
                                .foregroundStyle(.primary)
                            Text(filter.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        if settings.ratingFilter == filter {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Content Rating")
        } footer: {
            Text("Applies everywhere (Browse, Feed, Pools, Favorites). Posts above the selected rating are hidden.")
        }
    }

    private var gallerySection: some View {
        Section {
            ForEach(GalleryTilingMode.allCases) { mode in
                Button {
                    settings.galleryTilingMode = mode
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title)
                                .foregroundStyle(.primary)
                            Text(mode.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        if settings.galleryTilingMode == mode {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        } header: {
            Text("Gallery")
        } footer: {
            Text("Applies to Browse and Favorites. Scroll-to-current post in the viewer is preserved.")
        }
    }

    private func deleteServers(at offsets: IndexSet) {
        for index in offsets {
            let server = servers.servers[index]
            servers.remove(host: server.host)
        }
    }
}

private struct ServerRow: View {
    @Environment(ServerStore.self) private var servers
    let server: BooruServer

    var body: some View {
        HStack(spacing: 10) {
            NavigationLink {
                ServerDetailView(server: server)
            } label: {
                HStack(spacing: 10) {
                    Circle()
                        .fill(servers.color(for: server.host))
                        .frame(width: 12, height: 12)
                        .opacity(server.isEnabled ? 1 : 0.35)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(server.host)
                        HStack(spacing: 6) {
                            Text(server.flavor.title)
                            if server.isBuiltIn {
                                Text("Built-in")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 8)

                    keyIndicator
                }
                .contentShape(Rectangle())
            }

            Toggle("", isOn: enabledBinding)
                .labelsHidden()
        }
    }

    /// No icon once credentials are set; red when they're mandatory and missing; gray when optional.
    @ViewBuilder
    private var keyIndicator: some View {
        if server.supportsCredentials, !server.hasCredentials {
            Image(systemName: "key.fill")
                .font(.caption)
                .foregroundStyle(server.requiresCredentials ? Color.red : Color.secondary)
        }
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { server.isEnabled },
            set: { servers.setEnabled($0, host: server.host) }
        )
    }
}

private struct ServerDetailView: View {
    @Environment(ServerStore.self) private var servers
    let server: BooruServer

    @State private var userID: String = ""
    @State private var apiKey: String = ""

    private let swatchColumns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        Form {
            if server.supportsCredentials {
                credentialsSection
            }
            colorSection
        }
        .navigationTitle(server.host)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .onAppear {
            userID = server.userID ?? ""
            apiKey = server.apiKey ?? ""
        }
        .onDisappear(perform: persistCredentialsIfChanged)
    }

    private var credentialsSection: some View {
        Section {
            TextField(server.credentialUserFieldTitle, text: $userID)
                .textContentType(.username)
#if os(iOS)
                .keyboardType(server.flavor == .gelbooru ? .numberPad : .default)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
#endif
            TextField("API Key", text: $apiKey)
                .textContentType(.password)
#if os(iOS)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
#endif

            if !userID.isEmpty || !apiKey.isEmpty {
                Button("Clear", role: .destructive) {
                    userID = ""
                    apiKey = ""
                    servers.updateCredentials(host: server.host, apiKey: nil, userID: nil)
                }
            }
        } header: {
            Text("API Key")
        } footer: {
            Text(server.credentialsHelpText)
        }
    }

    private var colorSection: some View {
        Section {
            LazyVGrid(columns: swatchColumns, spacing: 12) {
                ForEach(ServerStore.selectableColorHexes, id: \.self) { hex in
                    swatch(hex)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Border Color")
        } footer: {
            Text("Used to outline posts from this server when two or more servers are enabled.")
        }
    }

    private func swatch(_ hex: String) -> some View {
        let isSelected = servers.colorHex(for: server.host).caseInsensitiveCompare(hex) == .orderedSame
        return Circle()
            .fill(Color(hex: hex))
            .frame(width: 34, height: 34)
            .overlay {
                Circle()
                    .strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 3)
            }
            .overlay {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                }
            }
            .contentShape(Circle())
            .onTapGesture {
                servers.updateColor(host: server.host, hex: hex)
            }
            .accessibilityLabel(Text(hex))
    }

    private func persistCredentialsIfChanged() {
        let newUser = userID.trimmingCharacters(in: .whitespaces)
        let newKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard newUser != (server.userID ?? "") || newKey != (server.apiKey ?? "") else { return }
        servers.updateCredentials(host: server.host, apiKey: newKey, userID: newUser)
    }
}

#Preview {
    SettingsPlaceholderView()
        .environment(AppSettingsStore.shared)
        .environment(ServerStore.shared)
}
