import Foundation

/// Time window for the Moebooru `post/popular_recent` endpoint.
enum PopularPeriod: String, CaseIterable, Identifiable, Sendable {
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
