import Foundation

enum BooruSiteFactory {
    static func makeSite(for server: BooruServer) -> any BooruSite & BooruBrowsing {
        switch server.flavor {
        case .moebooru: MoebooruSite(host: server.host)
        case .danbooru2: Danbooru2Site(host: server.host, login: server.userID, apiKey: server.apiKey)
        case .gelbooru: GelbooruSite(host: server.host, apiKey: server.apiKey, userID: server.userID)
        }
    }

    static func makeSite(host: String, flavor: BooruAPIFlavor) -> any BooruSite & BooruBrowsing {
        switch flavor {
        case .moebooru: MoebooruSite(host: host)
        case .danbooru2: Danbooru2Site(host: host)
        case .gelbooru: GelbooruSite(host: host)
        }
    }

    /// Convenience site used only for SwiftUI previews.
    static var previewSite: any BooruSite & BooruBrowsing {
        MoebooruSite(host: "yande.re")
    }
}
