import Foundation

struct KemonoAPIConfiguration: Sendable {
    var baseURL: URL
    var sessionCookie: String?

    static var current: KemonoAPIConfiguration {
        AppSettings.apiConfiguration
    }
}

/// HTTP client for kemono.cr API.
final class KemonoAPIClient: Sendable {
    private static let postSearchLimit = 20

    private let configuration: KemonoAPIConfiguration
    private let session: URLSession

    init(
        configuration: KemonoAPIConfiguration = .current,
        session: URLSession = KemonoURLSessionFactory.shared
    ) {
        self.configuration = configuration
        self.session = session
    }

    /// Connectivity check — streams API response and stops after the first creator object.
    /// Kemono ignores `limit` on `/creators` and can send 10+ MB; full download often times out on iOS.
    func testConnection() async throws -> String {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: "api/v1/creators"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: "a"),
        ]

        guard let url = components?.url else {
            throw KemonoAPIError.invalidURL
        }

        let request = makeRequest(url: url)
        let artists = try await KemonoStreamingHTTP.fetchArtists(request: request, limit: 1)
        let host = configuration.baseURL.host ?? configuration.baseURL.absoluteString

        if configuration.sessionCookie == nil {
            return "Connected to \(host). API reachable (no session cookie saved)."
        }
        return "Connected to \(host). API OK (\(artists.count) sample creator parsed)."
    }

    func searchArtists(query: String, limit: Int = 20, offset: Int = 0) async throws -> [KemonoArtistResult] {
        // Kemono ignores `q` server-side; the API returns the full creator catalog (~12 MB).
        // Filter client-side while streaming, same as kemono_gui_v6.py.
        let url = configuration.baseURL.appending(path: "api/v1/creators")

        let request = makeRequest(url: url)
        return try await KemonoStreamingHTTP.searchArtists(
            request: request,
            query: query,
            limit: limit,
            offset: offset
        )
    }

    /// Single request — downloads the full `/api/v1/creators` JSON, then parse locally.
    func fetchCreatorCatalog() async throws -> [KemonoArtistResult] {
        let url = configuration.baseURL.appending(path: "api/v1/creators")
        let data = try await performCatalogRequest(url: url)
        return try KemonoJSONParser.parseArtists(from: data)
    }

    func searchPosts(query: String, offset: Int = 0) async throws -> [KemonoPostResult] {
        var components = URLComponents(
            url: configuration.baseURL.appending(path: "api/v1/posts/search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "o", value: String(offset)),
        ]

        let data = try await performRequest(url: components?.url)
        let posts = try KemonoJSONParser.parsePosts(from: data)
        return Array(posts.prefix(Self.postSearchLimit))
    }

    /// Loads all posts for an author, paginating through `/posts?o=` (50 per page).
    func fetchAllArtistPosts(service: String, authorId: String) async throws -> [KemonoPostResult] {
        var allPosts: [KemonoPostResult] = []
        var offset = 0
        let pageSize = 50

        while true {
            let page = try await fetchArtistPostsPage(
                service: service,
                authorId: authorId,
                offset: offset
            )
            guard !page.isEmpty else { break }
            allPosts.append(contentsOf: page)
            if page.count < pageSize { break }
            offset += pageSize
        }

        return allPosts
    }

    func fetchArtistPostsPage(
        service: String,
        authorId: String,
        offset: Int
    ) async throws -> [KemonoPostResult] {
        var components = URLComponents(
            url: configuration.baseURL
                .appending(path: "api/v1")
                .appending(path: service)
                .appending(path: "user")
                .appending(path: authorId)
                .appending(path: "posts"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "o", value: String(offset)),
        ]

        let data = try await performArtistPostsRequest(url: components?.url)
        return try KemonoJSONParser.parsePosts(from: data)
    }

    func fetchArtistInfo(service: String, authorId: String) async throws -> KemonoArtistResult {
        let url = configuration.baseURL
            .appending(path: "api/v1")
            .appending(path: service)
            .appending(path: "user")
            .appending(path: authorId)

        let data = try await performRequest(url: url)
        let json = try JSONSerialization.jsonObject(with: data)

        if let object = json as? [String: Any],
           let error = object["error"] as? String, !error.isEmpty {
            throw KemonoAPIError.httpStatus(404, error)
        }

        guard let object = json as? [String: Any],
              let artist = KemonoJSONParser.parseArtist(from: object) else {
            throw KemonoAPIError.badResponse
        }

        return artist
    }

    func fetchPostDetail(service: String, authorId: String, postId: String) async throws -> KemonoPostDetail {
        let url = configuration.baseURL
            .appending(path: "api/v1")
            .appending(path: service)
            .appending(path: "user")
            .appending(path: authorId)
            .appending(path: "post")
            .appending(path: postId)

        let data = try await performRequest(url: url)
        return try KemonoJSONParser.parsePostDetail(from: data)
    }

    private func makeRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 180
        KemonoRequestHeaders.apply(to: &request, baseURL: configuration.baseURL)

        if let sessionCookie = configuration.sessionCookie {
            request.setValue("session=\(sessionCookie)", forHTTPHeaderField: "Cookie")
        }

        return request
    }

    private func performCatalogRequest(url: URL) async throws -> Data {
        var request = makeRequest(url: url)
        request.timeoutInterval = 600

        var lastError: KemonoAPIError = .badResponse

        for attempt in 0..<2 {
            do {
                let (data, response) = try await KemonoURLSessionFactory.catalog.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw KemonoAPIError.badResponse
                }

                if (200..<300).contains(httpResponse.statusCode) {
                    return try KemonoGzip.decompressIfNeeded(data)
                }

                let bodyPreview = Self.bodyPreview(from: data)
                lastError = .httpStatus(httpResponse.statusCode, bodyPreview)

                if Self.shouldRetry(statusCode: httpResponse.statusCode), attempt == 0 {
                    try await Task.sleep(nanoseconds: 800_000_000)
                    continue
                }

                throw lastError
            } catch let error as KemonoAPIError {
                throw error
            } catch let error as URLError {
                lastError = .network(error)
                if attempt == 0, Self.shouldRetry(urlError: error) {
                    try await Task.sleep(nanoseconds: 800_000_000)
                    continue
                }
                throw lastError
            } catch {
                lastError = .network(URLError(.unknown))
                throw lastError
            }
        }

        throw lastError
    }

    private func performArtistPostsRequest(url: URL?) async throws -> Data {
        guard let url else {
            throw KemonoAPIError.invalidURL
        }
        var request = makeRequest(url: url)
        request.timeoutInterval = 300
        return try await performDataRequest(request)
    }

    private func performRequest(url: URL?) async throws -> Data {
        guard let url else {
            throw KemonoAPIError.invalidURL
        }

        return try await performDataRequest(makeRequest(url: url))
    }

    private func performDataRequest(_ request: URLRequest) async throws -> Data {
        var lastError: KemonoAPIError = .badResponse

        for attempt in 0..<2 {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw KemonoAPIError.badResponse
                }

                if (200..<300).contains(httpResponse.statusCode) {
                    return try KemonoGzip.decompressIfNeeded(data)
                }

                let bodyPreview = Self.bodyPreview(from: data)
                lastError = .httpStatus(httpResponse.statusCode, bodyPreview)

                if Self.shouldRetry(statusCode: httpResponse.statusCode), attempt == 0 {
                    try await Task.sleep(nanoseconds: 800_000_000)
                    continue
                }

                throw lastError
            } catch let error as KemonoAPIError {
                throw error
            } catch let error as URLError {
                lastError = .network(error)
                if attempt == 0, Self.shouldRetry(urlError: error) {
                    try await Task.sleep(nanoseconds: 800_000_000)
                    continue
                }
                throw lastError
            } catch {
                lastError = .network(URLError(.unknown))
                throw lastError
            }
        }

        throw lastError
    }

    private static func shouldRetry(statusCode: Int) -> Bool {
        [429, 502, 503, 504].contains(statusCode)
    }

    private static func shouldRetry(urlError: URLError) -> Bool {
        [.timedOut, .networkConnectionLost, .cannotConnectToHost].contains(urlError.code)
    }

    private static func bodyPreview(from data: Data) -> String? {
        guard let text = String(data: data.prefix(300), encoding: .utf8) else {
            return nil
        }
        if text.localizedCaseInsensitiveContains("<html") {
            return nil
        }
        return text
    }
}

enum KemonoAPIError: LocalizedError {
    case invalidURL
    case badResponse
    case responseTooLarge
    case network(URLError)
    case httpStatus(Int, String?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case .badResponse:
            return "Unexpected server response."
        case .responseTooLarge:
            return "Server sent an oversized response. Use kemono.cr, save a fresh session cookie, then retry search."
        case .network(let error):
            switch error.code {
            case .secureConnectionFailed, .serverCertificateUntrusted, .clientCertificateRejected:
                return "TLS connection failed. Prefer kemono.cr if a mirror fails."
            case .timedOut:
                return "Request timed out. Use kemono.cr (same as Safari), save session cookie, then retry."
            case .networkConnectionLost:
                return "Connection lost while downloading results. Kemono may be sending a very large response — retry once on stable Wi‑Fi."
            case .notConnectedToInternet:
                return "No internet connection."
            case .cancelled:
                return "Request cancelled."
            default:
                return "Network error: \(error.localizedDescription)"
            }
        case .httpStatus(let code, let body):
            switch code {
            case 403:
                return "Access denied (403). Save a fresh session cookie in Settings or try another mirror."
            case 429:
                return "Too many requests (429). Wait a moment and try again."
            case 503, 502, 504:
                return "Kemono server is temporarily unavailable (HTTP \(code)). Retry or switch mirror in Settings."
            default:
                if let body, !body.isEmpty {
                    return "Server returned HTTP \(code): \(body)"
                }
                return "Server returned HTTP \(code)."
            }
        }
    }
}
