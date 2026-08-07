import Foundation
import SwiftData

@Model
final class CatalogSyncState {
    static let singletonID = "catalog"

    @Attribute(.unique) var id: String
    var lastSyncedAt: Date?
    var authorCount: Int
    var lastError: String?

    init(
        id: String = CatalogSyncState.singletonID,
        lastSyncedAt: Date? = nil,
        authorCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = id
        self.lastSyncedAt = lastSyncedAt
        self.authorCount = authorCount
        self.lastError = lastError
    }
}
