import Foundation

enum BooruHTTPError: LocalizedError {
    case invalidURL
    case badStatus(Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Invalid request URL."
        case .badStatus(let code): "Server returned HTTP \(code)."
        case .decodingFailed: "Could not decode server response."
        }
    }
}

enum BooruHTTPClient {
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpShouldSetCookies = true
        return URLSession(configuration: config)
    }()

    static func getJSON<T: Decodable>(
        url: URL,
        query: [String: String] = [:]
    ) async throws -> T {
        let data = try await getData(url: url, query: query)
        do {
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            return try decoder.decode(T.self, from: data)
        } catch {
            throw BooruHTTPError.decodingFailed
        }
    }

    static func getData(url: URL, query: [String: String] = [:]) async throws -> Data {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw BooruHTTPError.invalidURL
        }

        var items = components.queryItems ?? []
        for (key, value) in query where !value.isEmpty {
            items.append(URLQueryItem(name: key, value: value))
        }
        components.queryItems = items.isEmpty ? nil : items

        guard let requestURL = components.url else {
            throw BooruHTTPError.invalidURL
        }

        var request = URLRequest(url: requestURL)
        request.setValue("BooruVerse/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw BooruHTTPError.badStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw BooruHTTPError.badStatus(http.statusCode)
        }
        return data
    }
}
