import SwiftUI

struct SettingsPlaceholderView: View {
    @Environment(AppSettingsStore.self) private var settings
    @Environment(ServerStore.self) private var servers
    @Environment(AppNavigationCoordinator.self) private var navigation
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var showAddServer = false
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            settingsForm
#if os(macOS)
                .navigationTitle("")
#else
                .navigationTitle("Settings")
#endif
#if os(macOS)
                .formStyle(.grouped)
#endif
                .frame(maxWidth: settingsContentWidth)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .navigationDestination(for: AppNavigationCoordinator.SettingsRoute.self) { route in
                    switch route {
                    case .personalFeedSets:
                        PersonalFeedSetsView()
                    }
                }
                .sheet(isPresented: $showAddServer) {
                    AddServerView()
#if os(macOS)
                        .frame(minWidth: 440, idealWidth: 480, minHeight: 220, idealHeight: 260)
#endif
                }
                .onAppear { consumePendingRoute() }
                .onChange(of: navigation.pendingSettingsRoute) { _, _ in
                    consumePendingRoute()
                }
        }
    }

    private func consumePendingRoute() {
        guard let route = navigation.consumePendingSettingsRoute() else { return }
        path.append(route)
    }

    private var settingsContentWidth: CGFloat? {
#if os(macOS)
        horizontalSizeClass == .compact ? nil : 720
#else
        nil
#endif
    }

    @ViewBuilder
    private var settingsForm: some View {
        Form {
            serversSection
            personalFeedSection
            ratingSection
            gallerySection
        }
    }

    private var personalFeedSection: some View {
        Section {
            NavigationLink(value: AppNavigationCoordinator.SettingsRoute.personalFeedSets) {
                Label("Personal Feed", systemImage: "person.crop.rectangle.stack")
            }
        } header: {
            Text("Feed")
        } footer: {
            Text("Choose which saved tag sets appear in the Personal segment of Feed.")
        }
    }

    private var serversSection: some View {
        Section {
            ForEach(servers.servers) { server in
                ServerRow(server: server)
            }

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
#if os(macOS)
            Picker("Content Rating", selection: ratingBinding) {
                ForEach(RatingFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text(settings.ratingFilter.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
#else
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
#endif
        } header: {
            Text("Content Rating")
        } footer: {
            Text("Applies everywhere (Browse, Feed, Pools, Favorites). Posts above the selected rating are hidden.")
        }
    }

    private var gallerySection: some View {
        Section {
#if os(macOS)
            Picker("Gallery Layout", selection: tilingBinding) {
                ForEach(GalleryTilingMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()

            Text(settings.galleryTilingMode.description)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
#else
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
#endif

            Toggle("Load Full Quality in Viewer", isOn: fullQualityViewerBinding)
        } header: {
            Text("Gallery")
        } footer: {
            Text("Layout applies to Browse and Favorites. Full quality downloads the original file as soon as a post opens in the viewer (uses more data).")
        }
    }

    private var ratingBinding: Binding<RatingFilter> {
        Binding(
            get: { settings.ratingFilter },
            set: { settings.ratingFilter = $0 }
        )
    }

    private var tilingBinding: Binding<GalleryTilingMode> {
        Binding(
            get: { settings.galleryTilingMode },
            set: { settings.galleryTilingMode = $0 }
        )
    }

    private var fullQualityViewerBinding: Binding<Bool> {
        Binding(
            get: { settings.loadFullQualityInViewer },
            set: { settings.loadFullQualityInViewer = $0 }
        )
    }
}

private struct ServerRow: View {
    @Environment(ServerStore.self) private var servers
    let server: BooruServer

    var body: some View {
#if os(macOS)
        macRow
#else
        iosRow
#endif
    }

#if os(macOS)
    private var macRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Toggle("Enabled", isOn: enabledBinding)
                .labelsHidden()
                .toggleStyle(.checkbox)

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
                            .foregroundStyle(.primary)
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
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
        .contextMenu {
            if !server.isBuiltIn {
                Button("Remove Server", role: .destructive) {
                    servers.remove(host: server.host)
                }
            }
        }
    }
#endif

#if os(iOS)
    private var iosRow: some View {
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
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if !server.isBuiltIn {
                Button("Delete", role: .destructive) {
                    servers.remove(host: server.host)
                }
            }
        }
    }
#endif

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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let server: BooruServer

    @State private var userID: String = ""
    @State private var apiKey: String = ""

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
#if os(macOS)
        .formStyle(.grouped)
        .frame(maxWidth: horizontalSizeClass == .compact ? nil : 640)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
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
                .autocorrectionDisabled()
#if os(iOS)
                .keyboardType(server.flavor == .gelbooru ? .numberPad : .default)
                .textInputAutocapitalization(.never)
#endif
            SecureField("API Key", text: $apiKey)
                .textContentType(.password)
                .autocorrectionDisabled()

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
            // Avoid LazyVGrid inside Form on macOS — it collapses / clips badly.
            ColorSwatchGrid(
                selectedHex: servers.colorHex(for: server.host),
                onSelect: { hex in
                    servers.updateColor(host: server.host, hex: hex)
                }
            )
            .padding(.vertical, 4)
        } header: {
            Text("Border Color")
        } footer: {
            Text("Used to outline posts from this server when two or more servers are enabled.")
        }
    }

    private func persistCredentialsIfChanged() {
        let newUser = userID.trimmingCharacters(in: .whitespaces)
        let newKey = apiKey.trimmingCharacters(in: .whitespaces)
        guard newUser != (server.userID ?? "") || newKey != (server.apiKey ?? "") else { return }
        servers.updateCredentials(host: server.host, apiKey: newKey, userID: newUser)
    }
}

private struct ColorSwatchGrid: View {
    let selectedHex: String
    let onSelect: (String) -> Void

    private let columns = [GridItem(.adaptive(minimum: 36, maximum: 40), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ServerStore.selectableColorHexes, id: \.self) { hex in
                let isSelected = selectedHex.caseInsensitiveCompare(hex) == .orderedSame
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 32, height: 32)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.primary.opacity(isSelected ? 0.9 : 0), lineWidth: 3)
                    }
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .shadow(radius: 1)
                        }
                    }
                    .contentShape(Circle())
                    .onTapGesture { onSelect(hex) }
                    .accessibilityLabel(Text(hex))
            }
        }
#if os(macOS)
        // Give Form a real intrinsic height so the grid doesn't collapse to a single line.
        .frame(minHeight: 120, alignment: .topLeading)
#endif
    }
}

#Preview {
    SettingsPlaceholderView()
        .environment(AppSettingsStore.shared)
        .environment(ServerStore.shared)
        .environment(AppNavigationCoordinator())
}
