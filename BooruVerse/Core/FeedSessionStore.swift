import Foundation

/// Keeps the Feed view-model, channel, and scroll anchors alive across tab switches
/// and compact/regular layout rebuilds in RootView.
@MainActor
@Observable
final class FeedSessionStore {
    private(set) var model: BrowseViewModel
    private(set) var serversRevision: Int

    /// Last visible post id per feed channel (for scroll restore).
    private var scrollAnchorByChannel: [FeedChannel: String] = [:]

    private static let channelKey = "BooruVerse.feed.selectedChannel"

    init(sites: [any BooruSite & BooruBrowsing], serversRevision: Int) {
        self.serversRevision = serversRevision
        let model = BrowseViewModel(servers: sites, mode: .popular)
        if let raw = UserDefaults.standard.string(forKey: Self.channelKey),
           let channel = FeedChannel(rawValue: raw) {
            model.applyFeedChannel(channel)
        }
        self.model = model
    }

    func syncServersIfNeeded(sites: [any BooruSite & BooruBrowsing], revision: Int) {
        guard revision != serversRevision else { return }
        let channel = model.feedChannel
        serversRevision = revision
        let model = BrowseViewModel(servers: sites, mode: .popular)
        model.applyFeedChannel(channel)
        self.model = model
    }

    func persistChannel(_ channel: FeedChannel) {
        UserDefaults.standard.set(channel.rawValue, forKey: Self.channelKey)
    }

    func scrollAnchor(for channel: FeedChannel) -> String? {
        scrollAnchorByChannel[channel]
    }

    func setScrollAnchor(_ postID: String?, for channel: FeedChannel) {
        if let postID {
            scrollAnchorByChannel[channel] = postID
        } else {
            scrollAnchorByChannel.removeValue(forKey: channel)
        }
    }
}
