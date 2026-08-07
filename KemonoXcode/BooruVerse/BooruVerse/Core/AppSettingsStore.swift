import Foundation

/// Which post ratings are shown across every feed.
enum RatingFilter: String, CaseIterable, Identifiable, Sendable {
    case all
    case hideExplicit
    case safeOnly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Show All"
        case .hideExplicit: "Hide Explicit"
        case .safeOnly: "Safe Only"
        }
    }

    var description: String {
        switch self {
        case .all: "Safe, questionable, and explicit posts."
        case .hideExplicit: "Safe and questionable posts only."
        case .safeOnly: "Only safe posts."
        }
    }

    func allows(_ rating: BooruRating) -> Bool {
        switch self {
        case .all: true
        case .hideExplicit: rating != .explicit
        case .safeOnly: rating == .safe
        }
    }
}

@MainActor
@Observable
final class AppSettingsStore {
    static let shared = AppSettingsStore()

    private(set) var revision = 0

    var galleryTilingMode: GalleryTilingMode {
        didSet {
            guard galleryTilingMode != oldValue else { return }
            UserDefaults.standard.set(galleryTilingMode.rawValue, forKey: Keys.galleryTilingMode)
            revision += 1
        }
    }

    var ratingFilter: RatingFilter {
        didSet {
            guard ratingFilter != oldValue else { return }
            UserDefaults.standard.set(ratingFilter.rawValue, forKey: Keys.ratingFilter)
            revision += 1
        }
    }

    private enum Keys {
        static let galleryTilingMode = "BooruVerse.galleryTilingMode"
        static let ratingFilter = "BooruVerse.ratingFilter"
    }

    private init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.galleryTilingMode),
           raw != "chaotic",
           let mode = GalleryTilingMode(rawValue: raw) {
            galleryTilingMode = mode
        } else if UserDefaults.standard.string(forKey: Keys.galleryTilingMode) == "chaotic" {
            galleryTilingMode = .columns
            UserDefaults.standard.set(GalleryTilingMode.columns.rawValue, forKey: Keys.galleryTilingMode)
        } else {
            galleryTilingMode = .adaptive
        }

        if let raw = UserDefaults.standard.string(forKey: Keys.ratingFilter),
           let filter = RatingFilter(rawValue: raw) {
            ratingFilter = filter
        } else {
            ratingFilter = .all
        }
    }
}
