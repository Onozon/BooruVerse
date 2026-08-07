import Foundation
import SwiftData

@Model
final class RecentPost {
    @Attribute(.unique) var postKey: String
    var lastViewedAt: Date

    var post: Post?

    init(post: Post, lastViewedAt: Date = .now) {
        self.postKey = post.key
        self.lastViewedAt = lastViewedAt
        self.post = post
    }
}
