import Foundation
import SwiftData

@Model
final class Subscription {
    @Attribute(.unique) var authorKey: String
    var subscribedAt: Date

    var author: Author?

    init(author: Author, subscribedAt: Date = .now) {
        self.authorKey = author.key
        self.subscribedAt = subscribedAt
        self.author = author
    }
}
