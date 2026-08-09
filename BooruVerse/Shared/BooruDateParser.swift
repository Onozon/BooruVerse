import Foundation

nonisolated enum BooruDateParser {
    /// Tolerant `created_at` parsing across Moebooru / Danbooru / Gelbooru encodings.
    static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }

        if let seconds = Double(raw) {
            // Gelbooru often sends unix seconds; Moebooru may too.
            if seconds > 1_000_000_000_000 {
                return Date(timeIntervalSince1970: seconds / 1000)
            }
            if seconds > 1_000_000_000 {
                return Date(timeIntervalSince1970: seconds)
            }
        }

        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFractional.date(from: raw) { return date }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: raw) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd",
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: raw) { return date }
        }
        return nil
    }
}

/// Decodes string or numeric `created_at` fields from board APIs.
nonisolated struct FlexibleAPIDate: Decodable, Sendable {
    let date: Date?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            date = nil
            return
        }
        if let string = try? container.decode(String.self) {
            date = BooruDateParser.parse(string)
            return
        }
        if let value = try? container.decode(Double.self) {
            date = BooruDateParser.parse(String(value))
            return
        }
        if let value = try? container.decode(Int.self) {
            date = BooruDateParser.parse(String(value))
            return
        }
        date = nil
    }
}
