import Foundation
import SwiftData

@Model
final class Post {
    @Attribute(.unique) var key: String
    var service: String
    var authorId: String
    var postId: String
    var title: String
    var publishedAt: Date
    var previewURL: String?
    var isRead: Bool
    var contentHTML: String?
    var lastOpenedAt: Date?

    var author: Author?

    init(
        service: String,
        authorId: String,
        postId: String,
        title: String,
        publishedAt: Date,
        previewURL: String? = nil,
        isRead: Bool = false,
        contentHTML: String? = nil,
        lastOpenedAt: Date? = nil,
        author: Author? = nil
    ) {
        self.key = Post.makeKey(service: service, authorId: authorId, postId: postId)
        self.service = service
        self.authorId = authorId
        self.postId = postId
        self.title = title
        self.publishedAt = publishedAt
        self.previewURL = previewURL
        self.isRead = isRead
        self.contentHTML = contentHTML
        self.lastOpenedAt = lastOpenedAt
        self.author = author
    }

    static func makeKey(service: String, authorId: String, postId: String) -> String {
        "\(service):\(authorId):\(postId)"
    }
}
