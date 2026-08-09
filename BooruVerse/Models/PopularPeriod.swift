import Foundation

/// Feed capsule segments: Personal tag-set mix, then popular periods.
nonisolated enum FeedChannel: String, CaseIterable, Identifiable, Sendable {
    case personal
    case day
    case week
    case month

    var id: String { rawValue }

    var title: String {
        switch self {
        case .personal: "Personal"
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }

    var popularPeriod: PopularPeriod? {
        switch self {
        case .personal: nil
        case .day: .day
        case .week: .week
        case .month: .month
        }
    }

    init(period: PopularPeriod) {
        switch period {
        case .day: self = .day
        case .week: self = .week
        case .month: self = .month
        }
    }
}

/// Time window for the Moebooru `post/popular_recent` endpoint.
nonisolated enum PopularPeriod: String, CaseIterable, Identifiable, Sendable {
    case day = "1d"
    case week = "1w"
    case month = "1m"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }
}
