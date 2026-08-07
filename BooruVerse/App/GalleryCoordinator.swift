import SwiftUI

@MainActor
@Observable
final class GalleryCoordinator {
    private(set) var model: BrowseViewModel?
    private(set) var posts: [BooruPost] = []
    /// Globally-unique post identity (`BooruPost.globalID`).
    private(set) var selectedPostID: String?

    var isPresented: Bool {
        model != nil && selectedPostID != nil
    }

    func open(model: BrowseViewModel, postID: String) {
        guard model.posts.contains(where: { $0.globalID == postID }) else { return }
        self.model = model
        posts = model.posts
        selectedPostID = postID
    }

    func dismiss() {
        model = nil
        selectedPostID = nil
        posts = []
    }

    func setSelectedPostID(_ postID: String) {
        guard posts.contains(where: { $0.globalID == postID }) else { return }
        selectedPostID = postID
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
}
