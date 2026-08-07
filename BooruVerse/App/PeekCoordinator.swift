import SwiftUI

@MainActor
@Observable
final class PeekCoordinator {
    private(set) var model: BrowseViewModel?
    private(set) var postIndex: Int?

    var isPresented: Bool {
        guard let model, let postIndex else { return false }
        return model.posts.indices.contains(postIndex)
    }

    func open(model: BrowseViewModel, at index: Int) {
        guard model.posts.indices.contains(index) else { return }
        self.model = model
        postIndex = index
    }

    func dismiss() {
        model = nil
        postIndex = nil
    }

    func isOpen(for model: BrowseViewModel) -> Bool {
        self.model === model
    }

    var activePost: BooruPost? {
        guard let model, let postIndex, model.posts.indices.contains(postIndex) else { return nil }
        return model.posts[postIndex]
    }
}
