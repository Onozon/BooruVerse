import Foundation

struct KemonoArtistResult: Identifiable, Hashable, Sendable {
    var id: String { key }

    let key: String
    let service: String
    let authorId: String
    let name: String
    let avatarURL: String?
    let updatedAt: Date?

    nonisolated init(
        service: String,
        authorId: String,
        name: String,
        avatarURL: String? = nil,
        updatedAt: Date? = nil
    ) {
        self.key = "\(service):\(authorId)"
        self.service = service
        self.authorId = authorId
        self.name = name
        self.avatarURL = avatarURL
        self.updatedAt = updatedAt
    }
}

struct KemonoPostResult: Identifiable, Hashable, Sendable {
    var id: String { key }

    let key: String
    let service: String
    let authorId: String
    let postId: String
    let title: String
    let publishedAt: Date
    let previewURL: String?
    let authorName: String?

    nonisolated init(
        service: String,
        authorId: String,
        postId: String,
        title: String,
        publishedAt: Date,
        previewURL: String? = nil,
        authorName: String? = nil
    ) {
        self.key = "\(service):\(authorId):\(postId)"
        self.service = service
        self.authorId = authorId
        self.postId = postId
        self.title = title
        self.publishedAt = publishedAt
        self.previewURL = previewURL
        self.authorName = authorName
    }
}
