import Foundation
import SwiftData

@Model
final class RecentAuthor {
    @Attribute(.unique) var authorKey: String
    var lastViewedAt: Date

    var author: Author?

    init(author: Author, lastViewedAt: Date = .now) {
        self.authorKey = author.key
        self.lastViewedAt = lastViewedAt
        self.author = author
    }
}
