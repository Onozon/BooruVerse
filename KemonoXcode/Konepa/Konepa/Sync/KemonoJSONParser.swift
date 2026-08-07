import Foundation

nonisolated enum KemonoJSONParser {
    static func parseArtists(from data: Data) throws -> [KemonoArtistResult] {
        let json = try JSONSerialization.jsonObject(with: data)
        let objects = extractObjectArray(from: json)
        return objects.compactMap(parseArtistObject)
    }

    static func parsePosts(from data: Data) throws -> [KemonoPostResult] {
        let json = try JSONSerialization.jsonObject(with: data)
        let objects = extractObjectArray(from: json)
        return objects.compactMap(parsePostObject)
    }

    static func parsePostDetail(from data: Data) throws -> KemonoPostDetail {
        let json = try JSONSerialization.jsonObject(with: data)
        guard let object = extractPostObject(from: json) else {
            throw KemonoAPIError.badResponse
        }
        guard let detail = parsePostDetailObject(object) else {
            throw KemonoAPIError.badResponse
        }
        return detail
    }

    private static func extractPostObject(from json: Any) -> [String: Any]? {
        if let object = json as? [String: Any] {
            if let post = object["post"] as? [String: Any] {
                return post
            }
            if object["id"] != nil, object["service"] != nil {
                return object
            }
        }
        return nil
    }

    private static func parsePostDetailObject(_ object: [String: Any]) -> KemonoPostDetail? {
        guard let service = stringValue(object["service"]),
              let authorId = stringValue(object["user"]),
              let postId = stringValue(object["id"]) else {
            return nil
        }

        let title = stringValue(object["title"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false) ? title! : "Untitled"
        let publishedAt = parseTimestamp(object["published"]) ?? parseTimestamp(object["added"]) ?? .now
        let contentHTML = stringValue(object["content"]) ?? ""

        var mediaItems: [KemonoMediaItem] = []
        var seenPaths = Set<String>()

        func appendMedia(path: String?, name: String?, source: KemonoMediaItem.Source) {
            guard let path, !path.isEmpty, !seenPaths.contains(path) else { return }
            seenPaths.insert(path)
            let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackName = (resolvedName?.isEmpty == false) ? resolvedName! : (path as NSString).lastPathComponent
            mediaItems.append(
                KemonoMediaItem(
                    id: "\(source.rawValue):\(path)",
                    name: fallbackName,
                    path: path,
                    source: source
                )
            )
        }

        if let file = object["file"] as? [String: Any] {
            appendMedia(path: stringValue(file["path"]), name: stringValue(file["name"]), source: .file)
        }

        if let attachments = object["attachments"] as? [[String: Any]] {
            for attachment in attachments {
                appendMedia(
                    path: stringValue(attachment["path"]) ?? stringValue(attachment["url"]),
                    name: stringValue(attachment["name"]),
                    source: .attachment
                )
            }
        }

        if let embeds = object["embeds"] as? [[String: Any]] {
            for embed in embeds {
                appendMedia(
                    path: stringValue(embed["url"]) ?? stringValue(embed["path"]),
                    name: stringValue(embed["subject"]) ?? stringValue(embed["name"]),
                    source: .embed
                )
            }
        }

        if let embed = object["embed"] as? [String: Any], !embed.isEmpty {
            appendMedia(
                path: stringValue(embed["url"]) ?? stringValue(embed["path"]),
                name: stringValue(embed["subject"]) ?? stringValue(embed["name"]),
                source: .embed
            )
        }

        return KemonoPostDetail(
            service: service,
            authorId: authorId,
            postId: postId,
            title: resolvedTitle,
            contentHTML: contentHTML,
            publishedAt: publishedAt,
            mediaItems: mediaItems
        )
    }

    private static func extractObjectArray(from json: Any) -> [[String: Any]] {
        if let array = json as? [[String: Any]] {
            return array
        }
        if let object = json as? [String: Any] {
            for key in ["creators", "data", "results", "posts"] {
                if let array = object[key] as? [[String: Any]] {
                    return array
                }
            }
        }
        return []
    }

    static func parseArtist(from object: [String: Any]) -> KemonoArtistResult? {
        parseArtistObject(object)
    }

    private static func parseArtistObject(_ object: [String: Any]) -> KemonoArtistResult? {
        guard let service = stringValue(object["service"]),
              let authorId = stringValue(object["id"]),
              let name = stringValue(object["name"]), !name.isEmpty else {
            return nil
        }

        let avatar = stringValue(object["avatar"])
        let updatedAt = parseTimestamp(object["updated"]) ?? parseTimestamp(object["indexed"])

        return KemonoArtistResult(
            service: service,
            authorId: authorId,
            name: name,
            avatarURL: avatar,
            updatedAt: updatedAt
        )
    }

    private static func parsePostObject(_ object: [String: Any]) -> KemonoPostResult? {
        guard let service = stringValue(object["service"]),
              let authorId = stringValue(object["user"]),
              let postId = stringValue(object["id"]) else {
            return nil
        }

        let title = stringValue(object["title"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedTitle = (title?.isEmpty == false) ? title! : "Untitled"

        guard let publishedAt = parseTimestamp(object["published"]) ?? parseTimestamp(object["added"]) else {
            return nil
        }

        let previewURL = stringValue(object["thumbnail"])
            ?? (object["file"] as? [String: Any]).flatMap { stringValue($0["path"]) }
            ?? firstFilePath(in: object["files"])

        return KemonoPostResult(
            service: service,
            authorId: authorId,
            postId: postId,
            title: resolvedTitle,
            publishedAt: publishedAt,
            previewURL: previewURL
        )
    }

    private static func firstFilePath(in value: Any?) -> String? {
        guard let files = value as? [[String: Any]], let first = files.first else {
            return nil
        }
        return stringValue(first["path"])
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let int as Int:
            return String(int)
        case let double as Double:
            return String(Int(double))
        default:
            return nil
        }
    }

    private static func parseTimestamp(_ value: Any?) -> Date? {
        KemonoDateParser.parse(value)
    }
}

