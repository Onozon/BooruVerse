import Foundation
import SwiftUI

nonisolated struct BooruTag: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let postCount: Int
    let type: BooruTagType

    init(name: String, postCount: Int = 0, type: BooruTagType = .general) {
        self.id = name
        self.name = name
        self.postCount = postCount
        self.type = type
    }
}

nonisolated struct BooruTagGroup: Identifiable, Sendable {
    let type: BooruTagType
    let tags: [BooruTag]

    /// Stable identity: there is exactly one group per type on screen. Keeping this constant
    /// (instead of hashing the member names) lets SwiftUI diff tags in place when a tag's type
    /// resolves, rather than tearing down and re-laying-out the whole group.
    var id: Int { type.rawValue }
}

extension Array where Element == BooruTag {
    var groupedByType: [BooruTagGroup] {
        let grouped = Dictionary(grouping: self, by: \.type)
        return BooruTagType.displayOrder.compactMap { type in
            guard let tags = grouped[type], !tags.isEmpty else { return nil }
            let sorted = tags.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return BooruTagGroup(type: type, tags: sorted)
        }
    }
}

nonisolated enum BooruTagType: Int, Sendable, CaseIterable {
    case general = 0
    case artist = 1
    case copyright = 3
    case character = 4
    case meta = 5

    /// Moebooru / Danbooru 1.13.x tag types — see https://yande.re/help/api
    init(moebooruRaw: Int) {
        self = BooruTagType(rawValue: moebooruRaw) ?? .general
    }

    static let displayOrder: [BooruTagType] = [
        .copyright, .character, .artist, .general, .meta
    ]

    var label: String {
        switch self {
        case .general: "General"
        case .artist: "Artist"
        case .copyright: "Copyright"
        case .character: "Character"
        case .meta: "Meta"
        }
    }

    /// Classic Danbooru-style tag colors.
    var color: Color {
        switch self {
        case .artist: Color(red: 0.92, green: 0.31, blue: 0.31)
        case .copyright: Color(red: 0.72, green: 0.52, blue: 0.82)
        case .character: Color(red: 0.31, green: 0.72, blue: 0.39)
        case .general: Color(red: 0.39, green: 0.51, blue: 0.85)
        case .meta: Color(red: 0.55, green: 0.55, blue: 0.58)
        }
    }
}
