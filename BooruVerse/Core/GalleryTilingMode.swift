import Foundation

enum GalleryTilingMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Fixed-width columns with independent vertical stacking (Pinterest-style).
    case columns
    /// Equal-width columns; row height follows the tallest tile in the row.
    case adaptive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .columns: "Columns"
        case .adaptive: "Adaptive Rows"
        }
    }

    var description: String {
        switch self {
        case .columns:
            "Fixed column width with independent vertical stacks, like Pinterest."
        case .adaptive:
            "Equal column width with a shared row height based on the tallest image in each row."
        }
    }
}
