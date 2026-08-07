import Foundation

enum KemonoURLSessionFactory {
    static let configuration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 180
        configuration.waitsForConnectivity = false
        configuration.httpMaximumConnectionsPerHost = 4
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        return configuration
    }()

    /// Long-running full catalog download — longer idle timeout between chunks.
    static let catalogConfiguration: URLSessionConfiguration = {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 600
        configuration.waitsForConnectivity = true
        configuration.httpMaximumConnectionsPerHost = 1
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .always
        return configuration
    }()

    static let shared: URLSession = URLSession(configuration: configuration)

    static let catalog: URLSession = URLSession(configuration: catalogConfiguration)
}

private final class HandlerBox: @unchecked Sendable {
    var cancel: (() -> Void)?
}

private final class ArtistStreamHandler: NSObject, URLSessionDataDelegate {
    private var buffer = Data()
    private let limit: Int
    private var continuation: CheckedContinuation<[KemonoArtistResult], Error>?
    private var finished = false
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    init(limit: Int, continuation: CheckedContinuation<[KemonoArtistResult], Error>) {
        self.limit = limit
        self.continuation = continuation
    }

    func start(request: URLRequest) {
        let session = URLSession(configuration: KemonoURLSessionFactory.configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        dataTask = task
        task.resume()
    }

    func cancel() {
        dataTask?.cancel()
        if !finished {
            finish(with: .failure(URLError(.cancelled)))
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard !finished else {
            completionHandler(.cancel)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            finish(with: .failure(KemonoAPIError.badResponse))
            completionHandler(.cancel)
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            finish(with: .failure(KemonoAPIError.httpStatus(httpResponse.statusCode, nil)))
            completionHandler(.cancel)
            return
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }

        buffer.append(data)
        let parsed = KemonoPartialJSONParser.parseArtists(from: buffer, limit: limit)

        if parsed.count >= limit {
            finish(with: .success(Array(parsed.prefix(limit))))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }

        if let error = error as? URLError, error.code == .cancelled {
            return
        }

        if let error {
            finish(with: .failure(error))
            return
        }

        guard let response = task.response as? HTTPURLResponse else {
            finish(with: .failure(KemonoAPIError.badResponse))
            return
        }

        guard (200..<300).contains(response.statusCode) else {
            let preview = String(data: buffer.prefix(300), encoding: .utf8)
            finish(with: .failure(KemonoAPIError.httpStatus(response.statusCode, preview)))
            return
        }

        do {
            let artists = try KemonoJSONParser.parseArtists(from: buffer)
            finish(with: .success(Array(artists.prefix(limit))))
        } catch {
            let partial = KemonoPartialJSONParser.parseArtists(from: buffer, limit: limit)
            if partial.isEmpty {
                finish(with: .failure(error))
            } else {
                finish(with: .success(partial))
            }
        }
    }

    private func finish(with result: Result<[KemonoArtistResult], Error>) {
        guard !finished else { return }
        finished = true
        session?.finishTasksAndInvalidate()
        session = nil
        dataTask = nil

        switch result {
        case .success(let artists):
            continuation?.resume(returning: artists)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

private final class ArtistSearchStreamHandler: NSObject, URLSessionDataDelegate {
    private static let maxDownloadBytes = 15_000_000

    private let query: String
    private let limit: Int
    private let offset: Int
    private var parser = IncrementalArtistParser()
    private var matches: [KemonoArtistResult] = []
    private var downloadedBytes = 0
    private var continuation: CheckedContinuation<[KemonoArtistResult], Error>?
    private var finished = false
    private var session: URLSession?
    private var dataTask: URLSessionDataTask?

    init(
        query: String,
        limit: Int,
        offset: Int,
        continuation: CheckedContinuation<[KemonoArtistResult], Error>
    ) {
        self.query = query
        self.limit = limit
        self.offset = offset
        self.continuation = continuation
    }

    func start(request: URLRequest) {
        let session = URLSession(configuration: KemonoURLSessionFactory.configuration, delegate: self, delegateQueue: nil)
        self.session = session
        let task = session.dataTask(with: request)
        dataTask = task
        task.resume()
    }

    func cancel() {
        dataTask?.cancel()
        if !finished {
            finish(with: .failure(URLError(.cancelled)))
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard !finished else {
            completionHandler(.cancel)
            return
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            finish(with: .failure(KemonoAPIError.badResponse))
            completionHandler(.cancel)
            return
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            finish(with: .failure(KemonoAPIError.httpStatus(httpResponse.statusCode, nil)))
            completionHandler(.cancel)
            return
        }

        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !finished else { return }

        downloadedBytes += data.count
        let batch = parser.append(data)

        for artist in batch where KemonoArtistMatcher.matches(artist, query: query) {
            matches.append(artist)
            if matches.count >= offset + limit {
                finish(with: .success(Array(matches.dropFirst(offset).prefix(limit))))
                dataTask.cancel()
                return
            }
        }

        if downloadedBytes >= Self.maxDownloadBytes {
            finish(with: .success(Array(matches.dropFirst(offset).prefix(limit))))
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !finished else { return }

        if let error = error as? URLError, error.code == .cancelled {
            return
        }

        if let error {
            finish(with: .failure(error))
            return
        }

        finish(with: .success(Array(matches.dropFirst(offset).prefix(limit))))
    }

    private func finish(with result: Result<[KemonoArtistResult], Error>) {
        guard !finished else { return }
        finished = true
        session?.finishTasksAndInvalidate()
        session = nil
        dataTask = nil

        switch result {
        case .success(let artists):
            continuation?.resume(returning: artists)
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

enum KemonoStreamingHTTP {
    static func fetchArtists(request: URLRequest, limit: Int) async throws -> [KemonoArtistResult] {
        let box = HandlerBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let handler = ArtistStreamHandler(limit: limit, continuation: continuation)
                box.cancel = { handler.cancel() }
                handler.start(request: request)
            }
        } onCancel: {
            box.cancel?()
        }
    }

    static func searchArtists(
        request: URLRequest,
        query: String,
        limit: Int,
        offset: Int = 0
    ) async throws -> [KemonoArtistResult] {
        let box = HandlerBox()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let handler = ArtistSearchStreamHandler(
                    query: query,
                    limit: limit,
                    offset: offset,
                    continuation: continuation
                )
                box.cancel = { handler.cancel() }
                handler.start(request: request)
            }
        } onCancel: {
            box.cancel?()
        }
    }
}
