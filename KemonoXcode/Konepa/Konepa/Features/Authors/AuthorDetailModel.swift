import Foundation
import SwiftData

@MainActor
@Observable
final class AuthorDetailModel {
    var isLoading = false
    var errorMessage: String?
    var currentPage = 0

    let pageSize = 20

    func loadPosts(for author: Author, in context: ModelContext, force: Bool = false) async {
        if !force,
           !author.posts.isEmpty,
           author.syncState?.isFullySynced == true {
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let engine = SyncEngine(modelContext: context)

        do {
            try Task.checkCancellation()
            let count = try await engine.loadAuthorPosts(author)
            try Task.checkCancellation()
            currentPage = 0
            if count == 0 {
                errorMessage = "Server returned no posts for this author."
            }
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
