import Foundation

struct KemonoMediaItem: Identifiable, Hashable, Sendable {
    enum Source: String, Sendable {
        case file
        case attachment
        case embed
    }

    let id: String
    let name: String
    let path: String
    let source: Source

    var previewURL: String? {
        KemonoURLResolver.previewURL(for: path)
    }

    var fullURL: String? {
        KemonoURLResolver.fullMediaURL(for: path)
    }

    var isImage: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "bmp", "tiff"].contains(ext)
    }

    var isVideo: Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "webm", "mov", "m4v"].contains(ext)
    }
}

struct KemonoPostDetail: Sendable {
    let service: String
    let authorId: String
    let postId: String
    let title: String
    let contentHTML: String
    let publishedAt: Date
    let mediaItems: [KemonoMediaItem]

    var pageURL: URL? {
        URL(string: "\(AppSettings.baseURL.absoluteString)/\(service)/user/\(authorId)/post/\(postId)")
    }
}
