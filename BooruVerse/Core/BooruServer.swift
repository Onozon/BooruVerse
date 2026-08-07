import Foundation

/// A user-configurable booru instance (host + API flavor).
struct BooruServer: Identifiable, Codable, Hashable, Sendable {
    let host: String
    var flavor: BooruAPIFlavor
    var isEnabled: Bool
    var isBuiltIn: Bool
    /// API key (Gelbooru requires this; anonymous access returns HTTP 401).
    var apiKey: String?
    /// User ID that pairs with `apiKey` (Gelbooru).
    var userID: String?
    /// User-picked border color, stored as "#RRGGBB". `nil` = auto-assigned from the palette.
    var colorHex: String?

    var id: String { host }
    var displayName: String { host }

    /// Hosts that cannot function at all without API credentials.
    private static let hostsRequiringCredentials: Set<String> = ["gelbooru.com"]

    /// Whether this flavor can use API credentials. Credentials are optional for most servers
    /// (e.g. safebooru.org, anonymous Danbooru) and only unlock restricted content / higher limits.
    var supportsCredentials: Bool {
        flavor == .gelbooru || flavor == .danbooru2
    }

    /// Whether credentials are mandatory for this specific host (returns 401 otherwise).
    var requiresCredentials: Bool {
        supportsCredentials && BooruServer.hostsRequiringCredentials.contains(host)
    }

    var hasCredentials: Bool {
        !(apiKey ?? "").isEmpty && !(userID ?? "").isEmpty
    }

    /// Label for the identity field paired with `apiKey` (Gelbooru uses a numeric user id,
    /// Danbooru uses the account login/username).
    var credentialUserFieldTitle: String {
        switch flavor {
        case .danbooru2: "Username"
        default: "User ID"
        }
    }

    var credentialsHelpText: String {
        switch flavor {
        case .danbooru2:
            "Optional. Sign in on the site, open your account → API Key, and paste your username and a generated API key here to access restricted posts and higher limits."
        default:
            "Some Gelbooru servers (e.g. gelbooru.com) require these; others work without them. Sign in on the site, open Account → Options → API Access Credentials, and copy your User ID and API Key here."
        }
    }

    init(
        host: String,
        flavor: BooruAPIFlavor,
        isEnabled: Bool,
        isBuiltIn: Bool,
        apiKey: String? = nil,
        userID: String? = nil,
        colorHex: String? = nil
    ) {
        self.host = host
        self.flavor = flavor
        self.isEnabled = isEnabled
        self.isBuiltIn = isBuiltIn
        self.apiKey = apiKey
        self.userID = userID
        self.colorHex = colorHex
    }
}
