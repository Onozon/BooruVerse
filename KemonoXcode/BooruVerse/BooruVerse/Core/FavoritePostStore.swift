import Foundation

@MainActor
@Observable
final class FavoritePostStore {
    static let shared = FavoritePostStore()

    private(set) var revision = 0
    private var orderedIDsBySite: [String: [Int]] = [:]

    private init() {}

    func isFavorite(postID: Int, siteID: String) -> Bool {
        orderedIDs(for: siteID).contains(postID)
    }

    /// Favorite post IDs, most recently added first.
    func favoriteIDs(for siteID: String) -> [Int] {
        orderedIDs(for: siteID)
    }

    func toggle(postID: Int, siteID: String) {
        var ids = orderedIDs(for: siteID)
        if let index = ids.firstIndex(of: postID) {
            ids.remove(at: index)
        } else {
            ids.insert(postID, at: 0)
        }
        orderedIDsBySite[siteID] = ids
        saveToDisk(siteID: siteID, ids: ids)
        revision += 1
    }

    private func orderedIDs(for siteID: String) -> [Int] {
        if let cached = orderedIDsBySite[siteID] {
            return cached
        }
        let loaded = loadFromDisk(siteID: siteID)
        orderedIDsBySite[siteID] = loaded
        return loaded
    }

    private func loadFromDisk(siteID: String) -> [Int] {
        let key = storageKey(siteID: siteID)
        guard let data = UserDefaults.standard.data(forKey: key),
              var ids = try? JSONDecoder().decode([Int].self, from: data) else {
            return []
        }

        // Migrate legacy storage (ascending post IDs) to most-recent-first order.
        if ids.count > 1, ids == ids.sorted() {
            ids.reverse()
            saveToDisk(siteID: siteID, ids: ids)
        }

        return ids
    }

    private func saveToDisk(siteID: String, ids: [Int]) {
        let key = storageKey(siteID: siteID)
        guard let data = try? JSONEncoder().encode(ids) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private func storageKey(siteID: String) -> String {
        "BooruVerse.favoritePosts.\(siteID)"
    }
}
