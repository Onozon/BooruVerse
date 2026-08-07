import Foundation

/// Active tag search state — tags are AND-ed together like on booru sites.
struct TagQuery: Equatable, Sendable {
    var tags: [String] = []

    var searchString: String {
        tags.joined(separator: " ")
    }

    var isEmpty: Bool {
        tags.isEmpty
    }

    mutating func add(_ tag: String) {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard !tags.contains(normalized) else { return }
        tags.append(normalized)
    }

    mutating func remove(_ tag: String) {
        tags.removeAll { $0 == tag }
    }

    mutating func remove(at index: Int) {
        guard tags.indices.contains(index) else { return }
        tags.remove(at: index)
    }

    mutating func clear() {
        tags.removeAll()
    }
}
