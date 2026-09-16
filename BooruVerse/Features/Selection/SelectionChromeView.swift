import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#endif
#if canImport(GameController)
import GameController
#endif

/// Toolbar cluster: selection count + downloads status (left of Refresh).
struct SelectionChromeView: View {
    @Environment(SelectionStore.self) private var selection
    @Environment(DownloadStore.self) private var downloads
    @Environment(AppSettingsStore.self) private var settings

    @State private var showSelected = false
    @State private var showDownloads = false
    @State private var pickingFolder = false
    @State private var pendingFolderPosts: [BooruPost] = []

    /// Match system toolbar glyph size used by Refresh / other `Label` icons.
    private let toolbarGlyphSize: CGFloat = 17

    private var isActive: Bool {
        !selection.isEmpty || downloads.visible
    }

    var body: some View {
        Group {
            if isActive {
                HStack(spacing: 12) {
                    if !selection.isEmpty {
                        Button {
                            showSelected = true
                        } label: {
                            HStack(spacing: 4) {
                                Image(AppIcon.check)
                                    .appGlyph(size: toolbarGlyphSize)
                                Text("\(selection.count)")
                                    .font(.body.weight(.semibold).monospacedDigit())
                            }
                        }
                        .accessibilityLabel("Selected \(selection.count)")
                    }

                    if downloads.visible {
                        Button {
                            showDownloads = true
                        } label: {
                            Image(AppIcon.download)
                                .appGlyph(size: toolbarGlyphSize)
                                .foregroundStyle(downloads.hasFailed ? Color.red : Color.primary)
                        }
                        .accessibilityLabel("Downloads")
                    }
                }
            }
        }
#if os(iOS)
        .sheet(isPresented: $showSelected) {
            selectedSheet
        }
        .sheet(isPresented: $showDownloads) {
            downloadsSheet
        }
#else
        .popover(isPresented: $showSelected, arrowEdge: .bottom) {
            selectedSheet
                .frame(minWidth: 320, idealWidth: 360, minHeight: 280, idealHeight: 420)
        }
        .popover(isPresented: $showDownloads, arrowEdge: .bottom) {
            downloadsSheet
                .frame(minWidth: 320, idealWidth: 360, minHeight: 280, idealHeight: 420)
        }
#endif
        .fileImporter(
            isPresented: $pickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            let posts = pendingFolderPosts
            pendingFolderPosts = []
            guard case .success(let urls) = result, let url = urls.first else { return }
            downloads.enqueue(posts, destination: .directory(url))
            for post in posts {
                selection.remove(globalID: post.globalID)
            }
        }
    }

    private var selectedSheet: some View {
        NavigationStack {
            List {
                ForEach(selection.posts, id: \.globalID) { post in
                    HStack(spacing: 12) {
                        RemoteThumbnail(url: post.previewURL, contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        Text("\(post.serverID) #\(post.id)")
                            .font(.subheadline)
                            .lineLimit(1)

                        Spacer(minLength: 4)

                        Button {
                            selection.remove(globalID: post.globalID)
                            if selection.isEmpty {
                                showSelected = false
                            }
                        } label: {
                            Image(AppIcon.close)
                                .appGlyph(size: 16)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove")
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
#if os(iOS)
            .listStyle(.plain)
#endif
            .overlay {
                if selection.isEmpty {
                    ContentUnavailableView(
                        "No Selection",
                        systemImage: "checkmark.circle",
                        description: Text("Select posts from the grid or Peek.")
                    )
                }
            }
            .navigationTitle("Selected")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showSelected = false
                    } label: {
                        Image(AppIcon.close)
                            .appGlyph(size: 18)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if !selection.isEmpty {
                    selectedActionsBar
                }
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }

    private var selectedActionsBar: some View {
        HStack(spacing: 10) {
            Menu {
                Button("Photos") { downloadSelected(toPhotos: true) }
                Button("Save As…") { downloadSelected(toPhotos: false) }
            } label: {
                selectedActionLabel(title: "Save", appIcon: AppIcon.download)
            }
            .buttonStyle(.bordered)

            Button {
                favoriteSelected()
            } label: {
                selectedActionLabel(title: "Fav", appIcon: AppIcon.favorites)
            }
            .buttonStyle(.bordered)

            Button {
                selection.clear()
                showSelected = false
            } label: {
                selectedActionLabel(title: "Clear", appIcon: AppIcon.close, tint: .red)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func selectedActionLabel(title: String, appIcon: String, tint: Color? = nil) -> some View {
        VStack(spacing: 4) {
            Image(appIcon)
                .appGlyph(size: 18)
            Text(title)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(tint ?? Color.primary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var downloadsSheet: some View {
        NavigationStack {
            List {
                ForEach(downloads.jobs) { job in
                    HStack(spacing: 12) {
                        RemoteThumbnail(url: job.post.previewURL, contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(DownloadStore.fileName(for: job.post))
                                .font(.subheadline)
                                .lineLimit(1)
                            Text(statusText(for: job))
                                .font(.caption)
                                .foregroundStyle(job.status == .failed ? Color.red : Color.secondary)
                            if job.status == .running {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                }
            }
#if os(iOS)
            .listStyle(.plain)
#endif
            .overlay {
                if downloads.jobs.isEmpty {
                    ContentUnavailableView(
                        "No Downloads",
                        systemImage: "arrow.down.circle",
                        description: Text("Finished downloads clear automatically.")
                    )
                }
            }
            .navigationTitle("Downloads")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                if downloads.hasFailed {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Retry") {
                            downloads.retryFailed()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        showDownloads = false
                    } label: {
                        Image(AppIcon.close)
                            .appGlyph(size: 18)
                    }
                    .accessibilityLabel("Close")
                }
            }
        }
#if os(iOS)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
#endif
    }

    private func statusText(for job: DownloadStore.Job) -> String {
        switch job.status {
        case .queued: "Queued"
        case .running: "Downloading…"
        case .done: "Done"
        case .failed: job.error ?? "Failed"
        }
    }

    private func favoriteSelected() {
        let posts = selection.posts
        let entries = posts.map { FavoriteEntry(post: $0, folderID: FavoritePostStore.shared.lastFolderID) }
        guard !entries.isEmpty else { return }
        FavoritePostStore.shared.requestAdd(
            posts: entries,
            clearSelectionOnConfirm: true,
            allowMove: true
        )
        showSelected = false
    }

    private func downloadSelected(toPhotos: Bool) {
        showSelected = false
        if toPhotos {
            downloads.enqueue(selection.takeAll(), destination: .photos)
            return
        }

        if !settings.askDownloadFolder, let folder = settings.resolvedDownloadFolderURL {
            downloads.enqueue(selection.takeAll(), destination: .directory(folder))
            return
        }

#if os(macOS)
        if let folder = Self.pickFolderMac() {
            downloads.enqueue(selection.takeAll(), destination: .directory(folder))
        }
#else
        pendingFolderPosts = selection.posts
        pickingFolder = true
#endif
    }

#if os(macOS)
    private static func pickFolderMac() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose a folder for downloads"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
#endif
}

/// Round Remix checkbox used on grid / peek / viewer corners.
struct SelectionCheckboxButton: View {
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(isOn ? AppIcon.check : AppIcon.checkBlank)
                .appGlyph(size: 22)
                .foregroundStyle(isOn ? Color.accentColor : Color.white)
                .shadow(color: .black.opacity(0.45), radius: 2, y: 1)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isOn ? "Deselect" : "Select")
    }
}

enum SelectionInput {
    /// ⌘ (and Ctrl) held at click time — Mac / iPad hardware keyboard.
    static var commandHeld: Bool {
#if os(macOS)
        NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.control)
#elseif canImport(GameController)
        guard let input = GCKeyboard.coalesced?.keyboardInput else { return false }
        let command =
            input.button(forKeyCode: .leftGUI)?.isPressed == true
            || input.button(forKeyCode: .rightGUI)?.isPressed == true
        let control =
            input.button(forKeyCode: .leftControl)?.isPressed == true
            || input.button(forKeyCode: .rightControl)?.isPressed == true
        return command || control
#else
        false
#endif
    }
}
