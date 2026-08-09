import Foundation

/// Sidebar page-tag chrome, isolated from the post grid's observation graph.
/// Mutations here must not invalidate `PostResultsView` / gallery bindings on `BrowseViewModel`.
@MainActor
@Observable
final class PageTagChrome {
    var pageTags: [BooruTag] = []
    private(set) var pageTagsRevision = 0
    private(set) var tagIndexRevision = 0
    private(set) var isResolvingPageTagColors = false

    var pageTagGroups: [BooruTagGroup] {
        pageTags.groupedByType
    }

    func bumpTagIndexRevision() {
        tagIndexRevision += 1
    }

    func setResolving(_ value: Bool) {
        isResolvingPageTagColors = value
    }

    func replacePageTags(_ tags: [BooruTag]) {
        guard tags != pageTags else { return }
        pageTags = tags
        pageTagsRevision += 1
    }

    func clear() {
        pageTags = []
        pageTagsRevision += 1
        isResolvingPageTagColors = false
    }
}
