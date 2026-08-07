import Foundation

enum AppSettings {
    private enum Keys {
        static let baseURL = "konepa.baseURL"
        static let sessionCookie = "konepa.sessionCookie"
    }

    static let defaultBaseURL = URL(string: "https://kemono.cr")!

    static let mirrorCandidates: [URL] = [
        URL(string: "https://kemono.cr")!,
        URL(string: "https://kemono.party")!,
    ]

    static var baseURL: URL {
        get {
            guard let string = UserDefaults.standard.string(forKey: Keys.baseURL),
                  let url = URL(string: string) else {
                return defaultBaseURL
            }
            return url
        }
        set {
            UserDefaults.standard.set(newValue.absoluteString, forKey: Keys.baseURL)
        }
    }

    static var sessionCookie: String? {
        get {
            normalizeSessionCookie(UserDefaults.standard.string(forKey: Keys.sessionCookie))
        }
        set {
            if let normalized = normalizeSessionCookie(newValue) {
                UserDefaults.standard.set(normalized, forKey: Keys.sessionCookie)
            } else {
                UserDefaults.standard.removeObject(forKey: Keys.sessionCookie)
            }
        }
    }

    static var hasSessionCookie: Bool {
        sessionCookie != nil
    }

    static var sessionCookieLength: Int {
        sessionCookie?.count ?? 0
    }

    static var apiConfiguration: KemonoAPIConfiguration {
        KemonoAPIConfiguration(
            baseURL: baseURL,
            sessionCookie: sessionCookie
        )
    }

    static func normalizeSessionCookie(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }

        if value.lowercased().hasPrefix("session=") {
            value = String(value.dropFirst("session=".count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
            value = String(value.dropFirst().dropLast())
        }

        return value.isEmpty ? nil : value
    }
}
