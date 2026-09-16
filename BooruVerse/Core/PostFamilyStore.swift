import Foundation

/// Loads parent/child “other versions” for APIs that support `parent:<id>`.
@MainActor
@Observable
final class PostFamilyStore {
    static let shared = PostFamilyStore()

    private var cache: [String: [BooruPost]] = [:]
    private var inFlight: Set<String> = []

    func cachedFamily(for post: BooruPost) -> [BooruPost] {
        cache[post.globalID] ?? []
    }

    func loadIfNeeded(post: BooruPost) async {
        let flavor = ServerStore.shared.server(host: post.serverID)?.flavor
        guard flavor?.supportsPostFamily == true else { return }
        guard post.mayHaveFamily else { return }
        if cache[post.globalID] != nil { return }
        guard !inFlight.contains(post.globalID) else { return }

        inFlight.insert(post.globalID)
        defer { inFlight.remove(post.globalID) }

        guard let server = ServerStore.shared.server(host: post.serverID) else { return }
        let site = BooruSiteFactory.makeSite(for: server)
        let rootID = post.familyRootID

        do {
            var posts = try await site.fetchPosts(tags: "parent:\(rootID)", page: 1, limit: 100)
            if !posts.contains(where: { $0.id == rootID }),
               let root = try await site.fetchPost(id: rootID) {
                posts.insert(root, at: 0)
            }
            let family = Self.sortedFamily(posts, rootID: rootID)
            guard family.count > 1 else {
                cache[post.globalID] = []
                return
            }
            for member in family {
                cache[member.globalID] = family
            }
        } catch {
            cache[post.globalID] = []
        }
    }

    private static func sortedFamily(_ posts: [BooruPost], rootID: Int) -> [BooruPost] {
        var seen = Set<String>()
        let unique = posts.filter { seen.insert($0.globalID).inserted }
        return unique.sorted { lhs, rhs in
            if lhs.id == rootID { return true }
            if rhs.id == rootID { return false }
            return lhs.id < rhs.id
        }
    }
}
