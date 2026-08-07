import Foundation
import SwiftData

@Model
final class Author {
    @Attribute(.unique) var key: String
    var service: String
    var authorId: String
    var name: String
    var nameLowercased: String
    var avatarURL: String?
    var updatedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \Post.author)
    var posts: [Post] = []

    @Relationship(deleteRule: .cascade, inverse: \AuthorSyncState.author)
    var syncState: AuthorSyncState?

    init(
        service: String,
        authorId: String,
        name: String,
        avatarURL: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.key = Author.makeKey(service: service, authorId: authorId)
        self.service = service
        self.authorId = authorId
        self.name = name
        self.nameLowercased = name.lowercased()
        self.avatarURL = avatarURL
        self.updatedAt = updatedAt
    }

    func apply(_ result: KemonoArtistResult) {
        name = result.name
        nameLowercased = result.name.lowercased()
        avatarURL = result.avatarURL
        updatedAt = result.updatedAt
    }

    static func makeKey(service: String, authorId: String) -> String {
        "\(service):\(authorId)"
    }
}
