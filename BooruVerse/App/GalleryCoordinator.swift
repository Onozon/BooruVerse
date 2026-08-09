import SwiftUI

@MainActor
@Observable
final class GalleryCoordinator {
    private(set) var model: BrowseViewModel?
    private(set) var posts: [BooruPost] = []
    /// Globally-unique post identity (`BooruPost.globalID`).
    private(set) var selectedPostID: String?
    /// Survives `dismiss()` so the grid can scroll to the last viewed post.
    private(set) var returnPostID: String?

    var isPresented: Bool {
        model != nil && selectedPostID != nil
    }

    func open(model: BrowseViewModel, postID: String) {
        guard model.posts.contains(where: { $0.globalID == postID }) else { return }
        self.model = model
        posts = model.posts
        selectedPostID = postID
        returnPostID = postID
    }

    func dismiss() {
        returnPostID = selectedPostID ?? returnPostID
        model = nil
        selectedPostID = nil
        posts = []
    }

    func setSelectedPostID(_ postID: String) {
        guard posts.contains(where: { $0.globalID == postID }) else { return }
        selectedPostID = postID
        returnPostID = postID
    }

    func syncFromModel() {
        guard let model else { return }
        posts = model.posts
        if let selectedPostID, !posts.contains(where: { $0.globalID == selectedPostID }) {
            dismiss()
        }
    }

    func isOpen(for model: BrowseViewModel) -> Bool {
        self.model === model
    }

    func consumeReturnPostID() -> String? {
        defer { returnPostID = nil }
        return returnPostID
    }
}
