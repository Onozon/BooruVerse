import Foundation
import SwiftData

@Model
final class AuthorSyncState {
    @Attribute(.unique) var authorKey: String
    var newestKnownPublishedAt: Date?
    var oldestKnownPublishedAt: Date?
    var isFullySynced: Bool
    var lastSyncedAt: Date?

    var author: Author?

    init(author: Author) {
        self.authorKey = author.key
        self.isFullySynced = false
        self.author = author
    }
}
