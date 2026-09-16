import Foundation

/// App-wide multi-select of posts (survives tab/search changes).
@MainActor
@Observable
final class SelectionStore {
    static let shared = SelectionStore()

    private(set) var posts: [BooruPost] = []
    private var ids: Set<String> = []

    var count: Int { posts.count }
    var isEmpty: Bool { posts.isEmpty }
    /// Corner checkboxes on grid / viewer / peek while anything is selected.
    var showsCheckboxes: Bool { !posts.isEmpty }

    private init() {}

    func contains(_ globalID: String) -> Bool {
        ids.contains(globalID)
    }

    func contains(_ post: BooruPost) -> Bool {
        ids.contains(post.globalID)
    }

    func toggle(_ post: BooruPost) {
        if ids.contains(post.globalID) {
            remove(globalID: post.globalID)
        } else {
            posts.append(post)
            ids.insert(post.globalID)
        }
    }

    func select(_ post: BooruPost) {
        guard !ids.contains(post.globalID) else { return }
        posts.append(post)
        ids.insert(post.globalID)
    }

    func remove(globalID: String) {
        guard ids.remove(globalID) != nil else { return }
        posts.removeAll { $0.globalID == globalID }
    }

    func remove(at index: Int) {
        guard posts.indices.contains(index) else { return }
        ids.remove(posts[index].globalID)
        posts.remove(at: index)
    }

    func clear() {
        posts.removeAll()
        ids.removeAll()
    }

    /// Returns current posts and clears the selection (download / favorite batch).
    func takeAll() -> [BooruPost] {
        let copy = posts
        clear()
        return copy
    }
}
