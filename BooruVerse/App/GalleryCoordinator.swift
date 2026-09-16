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
    /// When false (random / peek family), pager posts are not replaced by the browse list.
    private(set) var followsBrowseList = true

    var isPresented: Bool {
        model != nil && selectedPostID != nil
    }

    func open(model: BrowseViewModel, postID: String) {
        guard model.posts.contains(where: { $0.globalID == postID }) else { return }
        open(model: model, posts: model.posts, selectedPostID: postID, followsBrowseList: true)
    }

    func open(
        model: BrowseViewModel,
        posts: [BooruPost],
        selectedPostID: String,
        followsBrowseList: Bool = false
    ) {
        guard posts.contains(where: { $0.globalID == selectedPostID }) else { return }
        self.model = model
        self.posts = posts
        self.selectedPostID = selectedPostID
        self.followsBrowseList = followsBrowseList
        returnPostID = selectedPostID
    }

    func dismiss() {
        returnPostID = selectedPostID ?? returnPostID
        model = nil
        selectedPostID = nil
        posts = []
        followsBrowseList = true
    }

    func setSelectedPostID(_ postID: String) {
        guard posts.contains(where: { $0.globalID == postID }) else { return }
        selectedPostID = postID
        returnPostID = postID
    }

    /// Jump to a related version, inserting it next to the current page when it is not in the pager.
    func selectRelated(_ post: BooruPost) {
        if !posts.contains(where: { $0.globalID == post.globalID }) {
            if let index = posts.firstIndex(where: { $0.globalID == selectedPostID }) {
                posts.insert(post, at: min(index + 1, posts.count))
            } else {
                posts.append(post)
            }
        }
        selectedPostID = post.globalID
        returnPostID = post.globalID
    }

    func syncFromModel() {
        guard followsBrowseList, let model else { return }
        let extras = posts.filter { extra in
            !model.posts.contains(where: { $0.globalID == extra.globalID })
        }
        posts = model.posts + extras
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
