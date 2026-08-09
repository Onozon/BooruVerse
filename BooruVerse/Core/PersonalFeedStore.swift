import Foundation

/// Persists which saved tag sets are included in the Personal feed.
/// Selection is independent of Browse presets — sets are opt-in only.
@MainActor
@Observable
final class PersonalFeedStore {
    static let shared = PersonalFeedStore()

    private(set) var revision = 0
    private(set) var selectedIDs: Set<UUID> = []
    private var didLoad = false

    private static let storageKey = "BooruVerse.personalFeed.selectedSetIDs"

    private init() {
        loadIfNeeded()
    }

    var personalSets: [SavedTagSet] {
        let all = SavedTagSetStore.shared.sets
        return all.filter { selectedIDs.contains($0.id) }
    }

    func isInPersonal(_ set: SavedTagSet) -> Bool {
        loadIfNeeded()
        return selectedIDs.contains(set.id)
    }

    func isInPersonal(id: UUID) -> Bool {
        loadIfNeeded()
        return selectedIDs.contains(id)
    }

    func setPersonal(_ set: SavedTagSet, enabled: Bool) {
        setPersonal(id: set.id, enabled: enabled)
    }

    func setPersonal(id: UUID, enabled: Bool) {
        loadIfNeeded()
        if enabled {
            selectedIDs.insert(id)
        } else {
            selectedIDs.remove(id)
        }
        persist()
        revision += 1
    }

    func remove(id: UUID) {
        loadIfNeeded()
        guard selectedIDs.remove(id) != nil else { return }
        persist()
        revision += 1
    }

    func reloadFromDisk() {
        didLoad = false
        loadIfNeeded()
        revision += 1
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true

        guard let raw = UserDefaults.standard.array(forKey: Self.storageKey) as? [String] else {
            selectedIDs = []
            return
        }
        selectedIDs = Set(raw.compactMap(UUID.init(uuidString:)))
    }

    private func persist() {
        let raw = selectedIDs.map(\.uuidString)
        UserDefaults.standard.set(raw, forKey: Self.storageKey)
    }
}
