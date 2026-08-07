import Foundation
import SwiftData

@MainActor
@Observable
final class PostDetailModel {
    var detail: KemonoPostDetail?
    var isLoading = false
    var errorMessage: String?

    func load(post: Post, in context: ModelContext) async {
        restoreCachedDetail(from: post)

        isLoading = detail == nil
        errorMessage = nil
        defer { isLoading = false }

        let client = KemonoAPIClient()

        do {
            let fetched = try await client.fetchPostDetail(
                service: post.service,
                authorId: post.authorId,
                postId: post.postId
            )
            detail = fetched
            PostRepository.applyDetail(fetched, to: post)
            PostRepository.recordRecentView(for: post, in: context)
            try context.save()
        } catch {
            if detail != nil {
                PostRepository.recordRecentView(for: post, in: context)
                try? context.save()
                errorMessage = "Showing cached content. \(error.localizedDescription)"
            } else if let cached = post.contentHTML, !cached.isEmpty {
                detail = KemonoPostDetail(
                    service: post.service,
                    authorId: post.authorId,
                    postId: post.postId,
                    title: post.title,
                    contentHTML: cached,
                    publishedAt: post.publishedAt,
                    mediaItems: placeholderMedia(from: post)
                )
                PostRepository.recordRecentView(for: post, in: context)
                try? context.save()
                errorMessage = "Showing cached content. \(error.localizedDescription)"
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func restoreCachedDetail(from post: Post) {
        guard detail == nil else { return }

        let media = placeholderMedia(from: post)
        guard let cached = post.contentHTML, !cached.isEmpty else {
            if !media.isEmpty {
                detail = KemonoPostDetail(
                    service: post.service,
                    authorId: post.authorId,
                    postId: post.postId,
                    title: post.title,
                    contentHTML: "",
                    publishedAt: post.publishedAt,
                    mediaItems: media
                )
            }
            return
        }

        detail = KemonoPostDetail(
            service: post.service,
            authorId: post.authorId,
            postId: post.postId,
            title: post.title,
            contentHTML: cached,
            publishedAt: post.publishedAt,
            mediaItems: media
        )
    }

    private func placeholderMedia(from post: Post) -> [KemonoMediaItem] {
        guard let preview = post.previewURL,
              let path = KemonoURLResolver.extractMediaPath(preview) else {
            return []
        }

        let name = (path as NSString).lastPathComponent
        return [
            KemonoMediaItem(
                id: "cached:file",
                name: name.isEmpty ? "Media" : name,
                path: path,
                source: .file
            )
        ]
    }
}
