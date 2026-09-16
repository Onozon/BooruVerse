import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#endif

struct PostImageContextMenu: View {
    @Bindable var model: BrowseViewModel
    let post: BooruPost
    @Environment(ServerStore.self) private var servers
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.openURL) private var openURL

    private var pageURL: URL? {
        guard let server = servers.server(host: post.serverID) else { return nil }
        return post.pageURL(flavor: server.flavor)
    }

    var body: some View {
        Button {
            model.toggleFavorite(post)
        } label: {
            if model.isFavorite(post) {
                Label("Remove from Favorites", appIcon: AppIcon.favoritesFill)
            } else {
                Label("Add to Favorites", appIcon: AppIcon.favorites)
            }
        }

        if model.isFavorite(post) {
            Button {
                model.requestMoveFavorite(post)
            } label: {
                Label("Move to Folder…", appIcon: AppIcon.folder)
            }
        }

        Button {
            DownloadStore.shared.enqueue([post], destination: .photos)
        } label: {
            Label("Save to Photos", appIcon: AppIcon.photo)
        }

        Button {
            saveAs()
        } label: {
            Label("Save As…", appIcon: AppIcon.save)
        }

        if let pageURL {
            Button {
                openURL(pageURL)
            } label: {
                Label("Open on Site", appIcon: AppIcon.site)
            }
        }
    }

    private func saveAs() {
        if !settings.askDownloadFolder, let folder = settings.resolvedDownloadFolderURL {
            DownloadStore.shared.enqueue([post], destination: .directory(folder))
            return
        }
#if os(macOS)
        if let folder = pickFolderMac() {
            DownloadStore.shared.enqueue([post], destination: .directory(folder))
        }
#else
        // Context menus can't present fileImporter reliably — use app Documents.
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        let folder = docs?.appendingPathComponent("BooruVerse", isDirectory: true)
        if let folder {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            DownloadStore.shared.enqueue([post], destination: .directory(folder))
        }
#endif
    }

#if os(macOS)
    private func pickFolderMac() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
#endif
}

struct PostImageActionBar: View {
    @Bindable var model: BrowseViewModel
    let post: BooruPost
    var usesLightContent = false
    @Environment(ServerStore.self) private var servers
    @Environment(AppSettingsStore.self) private var settings
    @Environment(\.openURL) private var openURL

    @State private var pickingFolder = false

    private var pageURL: URL? {
        guard let server = servers.server(host: post.serverID) else { return nil }
        return post.pageURL(flavor: server.flavor)
    }

    private var contentColor: Color {
        usesLightContent ? .white : .primary
    }

    private var favoriteColor: Color {
        model.isFavorite(post) ? .pink : contentColor
    }

    private var dividerColor: Color {
        usesLightContent ? .white.opacity(0.28) : Color.primary.opacity(0.2)
    }

    var body: some View {
        HStack(spacing: 0) {
            actionButton(
                title: model.isFavorite(post) ? "Favorited" : "Favorite",
                appIcon: model.isFavorite(post) ? AppIcon.favoritesFill : AppIcon.favorites,
                tint: favoriteColor
            ) {
                model.toggleFavorite(post)
            }

            Divider()
                .frame(height: 28)
                .overlay(dividerColor)

            actionButton(title: "Photos", appIcon: AppIcon.photo) {
                DownloadStore.shared.enqueue([post], destination: .photos)
            }

            Divider()
                .frame(height: 28)
                .overlay(dividerColor)

            actionButton(title: "Save As", appIcon: AppIcon.save) {
                saveAs()
            }

            if let pageURL {
                Divider()
                    .frame(height: 28)
                    .overlay(dividerColor)

                actionButton(title: "Site", appIcon: AppIcon.site) {
                    openURL(pageURL)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
        .fileImporter(
            isPresented: $pickingFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            DownloadStore.shared.enqueue([post], destination: .directory(url))
        }
    }

    private func saveAs() {
        if !settings.askDownloadFolder, let folder = settings.resolvedDownloadFolderURL {
            DownloadStore.shared.enqueue([post], destination: .directory(folder))
            return
        }
#if os(macOS)
        if let folder = pickFolderMac() {
            DownloadStore.shared.enqueue([post], destination: .directory(folder))
        }
#else
        pickingFolder = true
#endif
    }

#if os(macOS)
    private func pickFolderMac() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        guard panel.runModal() == .OK else { return nil }
        return panel.url
    }
#endif

    private func actionButton(
        title: String,
        appIcon: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(appIcon)
                    .appGlyph(size: 18)
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint ?? contentColor)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
