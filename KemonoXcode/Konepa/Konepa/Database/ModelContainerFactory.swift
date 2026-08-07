import Foundation
import SwiftData

enum KonepaSchema {
    static let models: [any PersistentModel.Type] = [
        Author.self,
        Post.self,
        Subscription.self,
        AuthorSyncState.self,
        RecentAuthor.self,
        RecentPost.self,
        CatalogSyncState.self,
    ]

    static var schema: Schema {
        Schema(models)
    }
}

enum ModelContainerFactory {
    private static let storeFilename = "Konepa.store"

    static func make(inMemory: Bool = false) -> ModelContainer {
        let configuration: ModelConfiguration

        if inMemory {
            configuration = ModelConfiguration(
                schema: KonepaSchema.schema,
                isStoredInMemoryOnly: true
            )
        } else {
            let storeURL = persistentStoreURL()
            ensureApplicationSupportDirectoryExists(at: storeURL)

            configuration = ModelConfiguration(
                schema: KonepaSchema.schema,
                url: storeURL
            )
        }

        do {
            return try ModelContainer(
                for: KonepaSchema.schema,
                configurations: [configuration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    private static func persistentStoreURL() -> URL {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            fatalError("Application Support directory is unavailable.")
        }

        return appSupport.appendingPathComponent(storeFilename, isDirectory: false)
    }

    /// SwiftData/Core Data expects Application Support to exist before opening the store.
    private static func ensureApplicationSupportDirectoryExists(at storeURL: URL) {
        let directory = storeURL.deletingLastPathComponent()

        if FileManager.default.fileExists(atPath: directory.path) {
            return
        }

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        } catch {
            fatalError("Could not create Application Support directory: \(error)")
        }
    }
}
