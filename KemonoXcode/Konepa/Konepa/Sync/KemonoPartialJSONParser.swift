import Foundation

nonisolated enum KemonoArtistMatcher {
    static func matches(_ artist: KemonoArtistResult, query: String) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return true }

        return artist.name.lowercased().contains(needle)
            || artist.service.lowercased().contains(needle)
            || artist.authorId.lowercased().contains(needle)
    }
}

nonisolated struct IncrementalArtistParser {
    private var buffer = Data()
    private var scanIndex: String.Index?

    mutating func append(_ chunk: Data) -> [KemonoArtistResult] {
        buffer.append(chunk)

        guard let text = String(data: buffer, encoding: .utf8) else {
            return []
        }

        if scanIndex == nil {
            guard let arrayStart = text.firstIndex(of: "[") else {
                return []
            }
            scanIndex = text.index(after: arrayStart)
        }

        var results: [KemonoArtistResult] = []
        var index = scanIndex!

        while index < text.endIndex {
            guard let objectStart = text[index...].firstIndex(of: "{") else {
                break
            }
            guard let objectEnd = findMatchingClosingBrace(in: text, openingBraceAt: objectStart) else {
                break
            }

            let objectJSON = String(text[objectStart...objectEnd])
            if let objectData = objectJSON.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: objectData) as? [String: Any],
               let artist = KemonoJSONParser.parseArtist(from: object) {
                results.append(artist)
            }

            index = text.index(after: objectEnd)
        }

        scanIndex = index
        return results
    }

    private func findMatchingClosingBrace(in text: String, openingBraceAt start: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                if character == "\"" {
                    inString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }

            index = text.index(after: index)
        }

        return nil
    }
}

nonisolated enum KemonoPartialJSONParser {
    static func parseArtists(from data: Data, limit: Int) -> [KemonoArtistResult] {
        if let complete = try? KemonoJSONParser.parseArtists(from: data) {
            return Array(complete.prefix(limit))
        }

        guard let text = String(data: data, encoding: .utf8),
              let arrayStart = text.firstIndex(of: "[") else {
            return []
        }

        var results: [KemonoArtistResult] = []
        var searchIndex = text.index(after: arrayStart)

        while results.count < limit, searchIndex < text.endIndex {
            guard let objectStart = text[searchIndex...].firstIndex(of: "{") else {
                break
            }
            guard let objectEnd = findMatchingClosingBrace(in: text, openingBraceAt: objectStart) else {
                break
            }

            let objectJSON = String(text[objectStart...objectEnd])
            if let objectData = objectJSON.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: objectData) as? [String: Any],
               let artist = KemonoJSONParser.parseArtist(from: object) {
                results.append(artist)
            }

            searchIndex = text.index(after: objectEnd)
        }

        return results
    }

    private static func findMatchingClosingBrace(in text: String, openingBraceAt start: String.Index) -> String.Index? {
        var depth = 0
        var inString = false
        var escaped = false
        var index = start

        while index < text.endIndex {
            let character = text[index]

            if inString {
                if escaped {
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else if character == "\"" {
                    inString = false
                }
            } else {
                if character == "\"" {
                    inString = true
                } else if character == "{" {
                    depth += 1
                } else if character == "}" {
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                }
            }

            index = text.index(after: index)
        }

        return nil
    }
}
