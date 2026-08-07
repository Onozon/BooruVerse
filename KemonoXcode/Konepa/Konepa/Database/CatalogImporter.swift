import Foundation
import SwiftData

/// Imports a full creator catalog into SwiftData after a single HTTP download.
enum CatalogImporter: Sendable {
    private static let saveInterval = 5_000

    nonisolated static func importCatalog(
        _ results: [KemonoArtistResult],
        container: ModelContainer,
        onProgress: @Sendable @escaping (Int) async -> Void
    ) async throws {
        let context = ModelContext(container)
        context.autosaveEnabled = false

        let existingAuthors = try context.fetch(FetchDescriptor<Author>())
        var authorsByKey = Dictionary(uniqueKeysWithValues: existingAuthors.map { ($0.key, $0) })

        for (index, result) in results.enumerated() {
            if let author = authorsByKey[result.key] {
                author.apply(result)
            } else {
                let author = Author(
                    service: result.service,
                    authorId: result.authorId,
                    name: result.name,
                    avatarURL: result.avatarURL,
                    updatedAt: result.updatedAt
                )
                context.insert(author)
                authorsByKey[result.key] = author
            }

            let processed = index + 1
            if processed == results.count || processed % saveInterval == 0 {
                try context.save()
                await onProgress(processed)
            }
        }
    }
}
