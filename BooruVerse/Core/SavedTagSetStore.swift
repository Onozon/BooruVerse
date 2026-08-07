import Foundation

struct SavedTagSet: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var tags: [String]
    var createdAt: Date

    init(id: UUID = UUID(), name: String, tags: [String], createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.tags = tags
        self.createdAt = createdAt
    }
}

@MainActor
@Observable
final class SavedTagSetStore {
    static let shared = SavedTagSetStore()

    private(set) var revision = 0
    private var loaded = false
    private var savedSets: [SavedTagSet] = []

    private static let storageKey = "BooruVerse.savedTagSets.global"
    private static let legacyKeyPrefix = "BooruVerse.savedTagSets."

    private init() {}

    var sets: [SavedTagSet] {
        loadIfNeeded()
        return savedSets
    }

    func save(name: String, tags: [String]) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !tags.isEmpty else { return }
        loadIfNeeded()
        savedSets.insert(SavedTagSet(name: trimmedName, tags: tags), at: 0)
        persist()
        revision += 1
    }

    func delete(_ set: SavedTagSet) {
        loadIfNeeded()
        savedSets.removeAll { $0.id == set.id }
        persist()
        revision += 1
    }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true

        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode([SavedTagSet].self, from: data) {
            savedSets = decoded
            return
        }

        // Migrate any legacy per-site sets into the global list (one-time).
        var migrated: [SavedTagSet] = []
        for (key, value) in UserDefaults.standard.dictionaryRepresentation()
        where key.hasPrefix(Self.legacyKeyPrefix) && key != Self.storageKey {
            if let data = value as? Data,
               let decoded = try? JSONDecoder().decode([SavedTagSet].self, from: data) {
                migrated.append(contentsOf: decoded)
            }
        }
        if !migrated.isEmpty {
            savedSets = migrated
            persist()
        }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(savedSets) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }
}
