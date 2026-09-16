import CoreGraphics
import Foundation

/// Which post ratings are shown across every feed.
enum RatingFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case hideExplicit
    case safeOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Show All"
        case .hideExplicit: "Hide Explicit"
        case .safeOnly: "Safe Only"
        }
    }

    var description: String {
        switch self {
        case .all: "Safe, sensitive, questionable, and explicit posts."
        case .hideExplicit: "Hides explicit; keeps safe, sensitive, and questionable."
        case .safeOnly: "Only general/safe posts (Danbooru sensitive is hidden)."
        }
    }

    func allows(_ rating: BooruRating) -> Bool {
        switch self {
        case .all: true
        case .hideExplicit: rating != .explicit
        case .safeOnly: rating == .safe
        }
    }
}

@MainActor
@Observable
final class AppSettingsStore {
    static let shared = AppSettingsStore()

    private(set) var revision = 0

    var galleryTilingMode: GalleryTilingMode {
        didSet {
            guard galleryTilingMode != oldValue else { return }
            UserDefaults.standard.set(galleryTilingMode.rawValue, forKey: Keys.galleryTilingMode)
            revision += 1
        }
    }

    var ratingFilter: RatingFilter {
        didSet {
            guard ratingFilter != oldValue else { return }
            UserDefaults.standard.set(ratingFilter.rawValue, forKey: Keys.ratingFilter)
            revision += 1
        }
    }

    /// When enabled, the fullscreen viewer fetches `fileURL` immediately instead of
    /// waiting for pinch / double-tap. Off by default to save bandwidth.
    var loadFullQualityInViewer: Bool {
        didSet {
            guard loadFullQualityInViewer != oldValue else { return }
            UserDefaults.standard.set(loadFullQualityInViewer, forKey: Keys.loadFullQualityInViewer)
            revision += 1
        }
    }

    /// Browse sidebar visibility (Mac custom split + iPad `NavigationSplitView`).
    /// Default `true`. Missing key → true; explicit `false` persists across launches.
    var showsBrowseSidebar: Bool {
        didSet {
            guard showsBrowseSidebar != oldValue else { return }
            UserDefaults.standard.set(showsBrowseSidebar, forKey: Keys.showsBrowseSidebar)
            revision += 1
        }
    }

    /// Favorites folder sidebar visibility. Same persistence rules as Browse.
    var showsFavoritesSidebar: Bool {
        didSet {
            guard showsFavoritesSidebar != oldValue else { return }
            UserDefaults.standard.set(showsFavoritesSidebar, forKey: Keys.showsFavoritesSidebar)
            revision += 1
        }
    }


    private var tileExtents: [GalleryScaleSection: CGFloat]

    /// Display path for Save As / batch file downloads. Empty → prompt each time (or askEveryTime).
    private(set) var downloadFolderPath: String = ""

    /// Security-scoped bookmark for the download folder (sandbox). Prefer this over the path string.
    private var downloadFolderBookmark: Data?

    /// When true, always prompt for a folder on file downloads even if a folder is set.
    var askDownloadFolder: Bool {
        didSet {
            guard askDownloadFolder != oldValue else { return }
            UserDefaults.standard.set(askDownloadFolder, forKey: Keys.askDownloadFolder)
            revision += 1
        }
    }

    /// Resolves the configured folder. Caller / `DownloadStore` must keep security scope for writes.
    var resolvedDownloadFolderURL: URL? {
        if let data = downloadFolderBookmark {
            var isStale = false
            #if os(macOS)
            let options: URL.BookmarkResolutionOptions = [.withSecurityScope]
            #else
            let options: URL.BookmarkResolutionOptions = []
            #endif
            guard let url = try? URL(
                resolvingBookmarkData: data,
                options: options,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                return nil
            }
            if isStale {
                refreshDownloadFolderBookmark(from: url)
            }
            return url
        }
        let trimmed = downloadFolderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed, isDirectory: true)
    }

    /// Persist a user-picked folder with a security-scoped bookmark when possible.
    func setDownloadFolder(_ url: URL) {
        storeDownloadFolder(url, bumpRevision: true)
    }

    func clearDownloadFolder() {
        downloadFolderBookmark = nil
        downloadFolderPath = ""
        UserDefaults.standard.removeObject(forKey: Keys.downloadFolderBookmark)
        UserDefaults.standard.set("", forKey: Keys.downloadFolderPath)
        revision += 1
    }

    private func refreshDownloadFolderBookmark(from url: URL) {
        storeDownloadFolder(url, bumpRevision: false)
    }

    private func storeDownloadFolder(_ url: URL, bumpRevision: Bool) {
        #if os(macOS)
        let bookmarkOptions: URL.BookmarkCreationOptions = [.withSecurityScope]
        #else
        let bookmarkOptions: URL.BookmarkCreationOptions = []
        #endif
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        if let data = try? url.bookmarkData(
            options: bookmarkOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        ) {
            downloadFolderBookmark = data
            UserDefaults.standard.set(data, forKey: Keys.downloadFolderBookmark)
        } else {
            downloadFolderBookmark = nil
            UserDefaults.standard.removeObject(forKey: Keys.downloadFolderBookmark)
        }
        downloadFolderPath = url.path
        UserDefaults.standard.set(downloadFolderPath, forKey: Keys.downloadFolderPath)
        if bumpRevision {
            revision += 1
        }
    }

    private enum Keys {
        static let galleryTilingMode = "BooruVerse.galleryTilingMode"
        static let ratingFilter = "BooruVerse.ratingFilter"
        static let loadFullQualityInViewer = "BooruVerse.loadFullQualityInViewer"
        static let showsBrowseSidebar = "BooruVerse.browse.showsSidebar"
        static let showsFavoritesSidebar = "BooruVerse.favorites.showsSidebar"
        static let downloadFolderPath = "BooruVerse.downloads.folderPath"
        static let downloadFolderBookmark = "BooruVerse.downloads.folderBookmark"
        static let askDownloadFolder = "BooruVerse.downloads.askEveryTime"
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.galleryTilingMode),
           raw != "chaotic",
           let mode = GalleryTilingMode(rawValue: raw) {
            galleryTilingMode = mode
        } else if UserDefaults.standard.string(forKey: Keys.galleryTilingMode) == "chaotic" {
            galleryTilingMode = .columns
            UserDefaults.standard.set(GalleryTilingMode.columns.rawValue, forKey: Keys.galleryTilingMode)
        } else {
            galleryTilingMode = .adaptive
        }

        if let raw = UserDefaults.standard.string(forKey: Keys.ratingFilter),
           let filter = RatingFilter(rawValue: raw) {
            ratingFilter = filter
        } else {
            ratingFilter = .all
        }

        loadFullQualityInViewer = UserDefaults.standard.bool(forKey: Keys.loadFullQualityInViewer)

        if UserDefaults.standard.object(forKey: Keys.showsBrowseSidebar) == nil {
            showsBrowseSidebar = true
        } else {
            showsBrowseSidebar = UserDefaults.standard.bool(forKey: Keys.showsBrowseSidebar)
        }

        if UserDefaults.standard.object(forKey: Keys.showsFavoritesSidebar) == nil {
            showsFavoritesSidebar = true
        } else {
            showsFavoritesSidebar = UserDefaults.standard.bool(forKey: Keys.showsFavoritesSidebar)
        }

        downloadFolderPath = UserDefaults.standard.string(forKey: Keys.downloadFolderPath) ?? ""
        downloadFolderBookmark = UserDefaults.standard.data(forKey: Keys.downloadFolderBookmark)
        askDownloadFolder = UserDefaults.standard.bool(forKey: Keys.askDownloadFolder)

        var extents: [GalleryScaleSection: CGFloat] = [:]
        for section in GalleryScaleSection.allCases {
            if UserDefaults.standard.object(forKey: section.defaultsKey) != nil {
                let value = CGFloat(UserDefaults.standard.double(forKey: section.defaultsKey))
                extents[section] = value > 0 ? value : GalleryThumbScale.defaultExtent
            } else {
                extents[section] = GalleryThumbScale.defaultExtent
            }
        }
        tileExtents = extents
    }

    func tileExtent(for section: GalleryScaleSection) -> CGFloat {
        tileExtents[section] ?? GalleryThumbScale.defaultExtent
    }

    func setTileExtent(_ value: CGFloat, for section: GalleryScaleSection) {
        let clamped = max(72, value)
        guard tileExtents[section] != clamped else { return }
        tileExtents[section] = clamped
        UserDefaults.standard.set(Double(clamped), forKey: section.defaultsKey)
        revision += 1
    }
}
