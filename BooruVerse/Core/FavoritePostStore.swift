import Foundation

struct FavoriteFolder: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
}

struct FavoriteEntry: Codable, Hashable, Sendable, Identifiable {
    var siteID: String
    var postID: Int
    var folderID: String
    /// Cached preview for folder picker / empty-state thumbnails (optional; older entries may lack it).
    var previewURLString: String?

    var id: String { globalID }
    var globalID: String { "\(siteID)#\(postID)" }

    var previewURL: URL? {
        guard let previewURLString else { return nil }
        return URL(string: previewURLString)
    }

    init(siteID: String, postID: Int, folderID: String, previewURLString: String? = nil) {
        self.siteID = siteID
        self.postID = postID
        self.folderID = folderID
        self.previewURLString = previewURLString
    }

    init(post: BooruPost, folderID: String) {
        self.siteID = post.serverID
        self.postID = post.id
        self.folderID = folderID
        self.previewURLString = post.previewURL?.absoluteString
    }
}

@MainActor
@Observable
final class FavoritePostStore {
    static let shared = FavoritePostStore()
    static let defaultFolderID = "favorites-default"

    private(set) var revision = 0
    private(set) var folders: [FavoriteFolder] = []
    /// Most recently added first.
    private(set) var entries: [FavoriteEntry] = []
    var lastFolderID: String = FavoritePostStore.defaultFolderID {
        didSet {
            guard lastFolderID != oldValue else { return }
            UserDefaults.standard.set(lastFolderID, forKey: Keys.lastFolder)
        }
    }
    /// Folder currently shown in the Favorites tab.
    var activeFolderID: String = FavoritePostStore.defaultFolderID {
        didSet {
            guard activeFolderID != oldValue else { return }
            UserDefaults.standard.set(activeFolderID, forKey: Keys.activeFolder)
            revision += 1
        }
    }

    /// Posts waiting for a folder choice (single or batch).
    private(set) var pendingAdds: [FavoriteEntry] = []
    /// When true, clear `SelectionStore` after a successful confirm (batch from chrome).
    private(set) var pendingClearsSelection = false
    /// Pending batch includes already-favorited posts (move to chosen folder).
    private(set) var pendingAllowsMove = false
    var isPresentingFolderPicker = false

    private enum Keys {
        static let folders = "BooruVerse.favorites.folders"
        static let entries = "BooruVerse.favorites.entries"
        static let lastFolder = "BooruVerse.favorites.lastFolder"
        static let activeFolder = "BooruVerse.favorites.activeFolder"
        static let legacyPrefix = "BooruVerse.favoritePosts."
    }

    private init() {
        load()
    }

    var defaultFolder: FavoriteFolder {
        folders.first { $0.id == Self.defaultFolderID }
            ?? FavoriteFolder(id: Self.defaultFolderID, name: "Favorites")
    }

    func isFavorite(postID: Int, siteID: String) -> Bool {
        entries.contains { $0.siteID == siteID && $0.postID == postID }
    }

    func folderID(forPostID postID: Int, siteID: String) -> String? {
        entries.first { $0.siteID == siteID && $0.postID == postID }?.folderID
    }

    /// Favorite post IDs in `folderID` for a site, most-recent-first.
    func favoriteIDs(for siteID: String, folderID: String) -> [Int] {
        entries.compactMap { entry in
            guard entry.siteID == siteID, entry.folderID == folderID else { return nil }
            return entry.postID
        }
    }

    /// All favorite IDs for a site across folders (legacy helper).
    func favoriteIDs(for siteID: String) -> [Int] {
        entries.compactMap { entry in
            entry.siteID == siteID ? entry.postID : nil
        }
    }

    func postCount(in folderID: String) -> Int {
        entries.reduce(0) { $0 + ($1.folderID == folderID ? 1 : 0) }
    }

    /// Most-recent entries in a folder that have a cached preview (for picker thumbnails).
    func previewEntries(in folderID: String, limit: Int) -> [FavoriteEntry] {
        var result: [FavoriteEntry] = []
        for entry in entries where entry.folderID == folderID {
            guard entry.previewURL != nil else { continue }
            result.append(entry)
            if result.count >= limit { break }
        }
        return result
    }

    /// Fill missing preview URLs after favorites are refetched from the network.
    func backfillPreviews(from posts: [BooruPost]) {
        var changed = false
        for post in posts {
            guard let url = post.previewURL?.absoluteString else { continue }
            guard let index = entries.firstIndex(where: {
                $0.siteID == post.serverID && $0.postID == post.id
            }) else { continue }
            if entries[index].previewURLString != url {
                entries[index].previewURLString = url
                changed = true
            }
        }
        guard changed else { return }
        save()
        // No revision bump — previews are cosmetic for the picker.
    }

    func unfavorite(postID: Int, siteID: String) {
        let before = entries.count
        entries.removeAll { $0.siteID == siteID && $0.postID == postID }
        guard entries.count != before else { return }
        save()
        revision += 1
    }

    /// If already favorited → remove. Otherwise present folder picker.
    func toggleOrRequestAdd(_ post: BooruPost) {
        if isFavorite(postID: post.id, siteID: post.serverID) {
            unfavorite(postID: post.id, siteID: post.serverID)
        } else {
            requestAdd(posts: [FavoriteEntry(post: post, folderID: lastFolderID)])
        }
    }

    /// Present folder picker. When `allowMove` is true, already-favorited posts are included and moved.
    func requestAdd(
        posts: [FavoriteEntry],
        clearSelectionOnConfirm: Bool = false,
        allowMove: Bool = false
    ) {
        let targets: [FavoriteEntry]
        if allowMove {
            targets = posts
        } else {
            targets = posts.filter { !isFavorite(postID: $0.postID, siteID: $0.siteID) }
        }
        guard !targets.isEmpty else { return }
        pendingAdds = targets
        pendingClearsSelection = clearSelectionOnConfirm
        pendingAllowsMove = allowMove
        isPresentingFolderPicker = true
    }

    func cancelPendingAdd() {
        pendingAdds = []
        pendingClearsSelection = false
        pendingAllowsMove = false
        isPresentingFolderPicker = false
    }

    func confirmPendingAdd(folderID: String) {
        let target = resolvedFolderID(folderID)
        for post in pendingAdds {
            add(
                postID: post.postID,
                siteID: post.siteID,
                folderID: target,
                previewURLString: post.previewURLString
            )
        }
        lastFolderID = target
        let shouldClearSelection = pendingClearsSelection
        pendingAdds = []
        pendingClearsSelection = false
        pendingAllowsMove = false
        isPresentingFolderPicker = false
        save()
        revision += 1
        if shouldClearSelection {
            SelectionStore.shared.clear()
        }
    }

    func confirmPendingAddNewFolder(name: String) {
        let id = createFolder(name: name)
        guard !id.isEmpty else { return }
        confirmPendingAdd(folderID: id)
    }

    @discardableResult
    func createFolder(name: String) -> String {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return "" }
        let folder = FavoriteFolder(id: UUID().uuidString, name: cleaned)
        folders.append(folder)
        lastFolderID = folder.id
        save()
        revision += 1
        return folder.id
    }

    func renameFolder(id: String, name: String) {
        let cleaned = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty, id != Self.defaultFolderID else { return }
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[index].name = cleaned
        save()
        revision += 1
    }

    func deleteFolder(id: String, deletePosts: Bool) {
        guard id != Self.defaultFolderID else { return }
        if deletePosts {
            entries.removeAll { $0.folderID == id }
        } else {
            for index in entries.indices where entries[index].folderID == id {
                entries[index].folderID = Self.defaultFolderID
            }
        }
        folders.removeAll { $0.id == id }
        if lastFolderID == id { lastFolderID = Self.defaultFolderID }
        if activeFolderID == id { activeFolderID = Self.defaultFolderID }
        save()
        revision += 1
    }

    private func add(postID: Int, siteID: String, folderID: String, previewURLString: String? = nil) {
        let target = resolvedFolderID(folderID)
        if let index = entries.firstIndex(where: { $0.siteID == siteID && $0.postID == postID }) {
            entries[index].folderID = target
            if let previewURLString {
                entries[index].previewURLString = previewURLString
            }
            let entry = entries.remove(at: index)
            entries.insert(entry, at: 0)
        } else {
            entries.insert(
                FavoriteEntry(
                    siteID: siteID,
                    postID: postID,
                    folderID: target,
                    previewURLString: previewURLString
                ),
                at: 0
            )
        }
    }

    private func resolvedFolderID(_ folderID: String) -> String {
        if folders.contains(where: { $0.id == folderID }) {
            return folderID
        }
        return Self.defaultFolderID
    }

    private func ensureDefaultFolder() {
        if !folders.contains(where: { $0.id == Self.defaultFolderID }) {
            folders.insert(FavoriteFolder(id: Self.defaultFolderID, name: "Favorites"), at: 0)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Keys.folders),
           let decoded = try? JSONDecoder().decode([FavoriteFolder].self, from: data) {
            folders = decoded
        }
        ensureDefaultFolder()

        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: Keys.entries),
           let decoded = try? JSONDecoder().decode([FavoriteEntry].self, from: data) {
            entries = decoded
            // Remigrate if we somehow persisted an empty list while legacy keys remain.
            if entries.isEmpty, hasLegacyFavoriteKeys() {
                migrateLegacyIDs()
            } else {
                // Legacy keys are obsolete once entries exist.
                clearLegacyFavoriteKeys()
            }
        } else {
            migrateLegacyIDs()
        }

        lastFolderID = defaults.string(forKey: Keys.lastFolder) ?? Self.defaultFolderID
        if !folders.contains(where: { $0.id == lastFolderID }) {
            lastFolderID = Self.defaultFolderID
        }

        let savedActive = defaults.string(forKey: Keys.activeFolder) ?? lastFolderID
        activeFolderID = folders.contains(where: { $0.id == savedActive })
            ? savedActive
            : Self.defaultFolderID

        for index in entries.indices where !folders.contains(where: { $0.id == entries[index].folderID }) {
            entries[index].folderID = Self.defaultFolderID
        }
    }

    private func hasLegacyFavoriteKeys() -> Bool {
        UserDefaults.standard.dictionaryRepresentation().keys
            .contains { $0.hasPrefix(Keys.legacyPrefix) }
    }

    private func clearLegacyFavoriteKeys() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Keys.legacyPrefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private func migrateLegacyIDs() {
        var perSite: [(siteID: String, ids: [Int])] = []
        let defaults = UserDefaults.standard
        let keys = defaults.dictionaryRepresentation().keys
            .filter { $0.hasPrefix(Keys.legacyPrefix) }
            .sorted()
        for key in keys {
            let siteID = String(key.dropFirst(Keys.legacyPrefix.count))
            guard let data = defaults.data(forKey: key),
                  var ids = try? JSONDecoder().decode([Int].self, from: data) else { continue }
            // Legacy lists were sometimes stored ascending; newest-first is preferred.
            if ids.count > 1, ids == ids.sorted() {
                ids.reverse()
            }
            perSite.append((siteID, ids))
        }

        // Interleave by index so multi-server recency is roughly preserved.
        var migrated: [FavoriteEntry] = []
        var row = 0
        var added = true
        while added {
            added = false
            for (siteID, ids) in perSite where row < ids.count {
                migrated.append(
                    FavoriteEntry(siteID: siteID, postID: ids[row], folderID: Self.defaultFolderID)
                )
                added = true
            }
            row += 1
        }

        var seen = Set<String>()
        entries = migrated.filter { seen.insert($0.globalID).inserted }
        save()
        clearLegacyFavoriteKeys()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(folders) {
            UserDefaults.standard.set(data, forKey: Keys.folders)
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Keys.entries)
        }
        UserDefaults.standard.set(lastFolderID, forKey: Keys.lastFolder)
        UserDefaults.standard.set(activeFolderID, forKey: Keys.activeFolder)
    }
}
