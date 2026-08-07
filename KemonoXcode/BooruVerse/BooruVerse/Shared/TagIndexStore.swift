import Foundation

@MainActor
@Observable
final class TagIndexStore {
    static let shared = TagIndexStore()

    private(set) var cachedCounts: [String: Int] = [:]
    private(set) var revision = 0

    private var typesBySite: [String: [String: BooruTagType]] = [:]

    private init() {}

    func cachedCount(for siteID: String) -> Int {
        cachedCounts[siteID] ?? typesBySite[siteID]?.count ?? 0
    }

    func type(for name: String, siteID: String) -> BooruTagType? {
        typesBySite[siteID]?[name]
    }

    func loadCache(siteID: String) {
        guard typesBySite[siteID] == nil else { return }
        loadFromDisk(siteID: siteID)
    }

    func merge(_ tags: [BooruTag], siteID: String) {
        guard !tags.isEmpty else { return }

        var map = typesBySite[siteID] ?? [:]
        for tag in tags where !tag.name.isEmpty {
            map[tag.name] = tag.type
        }
        typesBySite[siteID] = map
        cachedCounts[siteID] = map.count
        revision += 1
    }

    func resolveMissing(
        names: [String],
        site: any BooruSite & BooruBrowsing,
        siteID: String,
        onUpdate: (@MainActor () -> Void)? = nil
    ) async {
        let missing = Array(Set(names)).filter { name in
            !name.isEmpty && type(for: name, siteID: siteID) == nil
        }
        guard !missing.isEmpty else { return }

        let fetched = await site.fetchTagTypes(for: missing, onBatch: onUpdate)
        merge(fetched, siteID: siteID)
        onUpdate?()

        let resolved = Set(fetched.map(\.name))
        let notFound = missing.filter { !resolved.contains($0) }
        if !notFound.isEmpty {
            merge(
                notFound.map { BooruTag(name: $0, postCount: 0, type: .general) },
                siteID: siteID
            )
            AppDebug.log("TagIndex", "cached \(notFound.count) unknown tags as general")
            onUpdate?()
        }

        saveToDisk(siteID: siteID)
    }

    private func loadFromDisk(siteID: String) {
        let url = cacheURL(siteID: siteID)
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(TagIndexFile.self, from: data),
              file.siteID == siteID else {
            return
        }

        var map: [String: BooruTagType] = [:]
        for (name, raw) in file.tags where !name.isEmpty {
            map[name] = BooruTagType(moebooruRaw: raw)
        }
        typesBySite[siteID] = map
        cachedCounts[siteID] = map.count
        revision += 1
        AppDebug.log("TagIndex", "loaded \(map.count) tags from cache")
    }

    private func saveToDisk(siteID: String) {
        guard let map = typesBySite[siteID], !map.isEmpty else { return }

        let file = TagIndexFile(
            siteID: siteID,
            savedAt: Date(),
            tags: Dictionary(uniqueKeysWithValues: map.map { ($0.key, $0.value.rawValue) })
        )

        let url = cacheURL(siteID: siteID)
        guard let data = try? JSONEncoder().encode(file) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func cacheURL(siteID: String) -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BooruVerse/tag-index", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("\(siteID).json")
    }
}

private struct TagIndexFile: Codable {
    let siteID: String
    let savedAt: Date
    let tags: [String: Int]
}
