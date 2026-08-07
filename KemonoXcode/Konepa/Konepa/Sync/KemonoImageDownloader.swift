import Foundation

struct KemonoImageLoadResult: Sendable {
    let data: Data
    let sourceURL: String
    let usedPreviewFallback: Bool
}

/// Limits parallel image downloads to reduce first-open jank.
actor KemonoImageConcurrency {
    static let shared = KemonoImageConcurrency(limit: 4)

    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = limit
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        running += 1
    }

    func release() {
        running = max(running - 1, 0)
        if let next = waiters.first {
            waiters.removeFirst()
            next.resume()
        }
    }
}

/// Downloads kemono media with redirect filtering and URL fallbacks.
enum KemonoImageDownloader {
    static func load(pathOrURL: String?, resolution: KemonoImageResolution) async -> KemonoImageLoadResult? {
        let candidates = KemonoURLResolver.loadCandidates(for: pathOrURL, resolution: resolution)
        guard !candidates.isEmpty else { return nil }

        let previewURL = KemonoURLResolver.previewURL(for: pathOrURL)

        await KemonoImageConcurrency.shared.acquire()
        defer { Task { await KemonoImageConcurrency.shared.release() } }

        for (index, urlString) in candidates.enumerated() {
            guard let url = URL(string: urlString) else { continue }

            do {
                if let data = try await download(url: url, preferDirectSession: isPreviewCDN(url)) {
                    let usedPreviewFallback = resolution == .full
                        && previewURL != nil
                        && urlString == previewURL
                    return KemonoImageLoadResult(
                        data: data,
                        sourceURL: urlString,
                        usedPreviewFallback: usedPreviewFallback
                    )
                }
            } catch {
                continue
            }

            if index < candidates.count - 1 {
                try? await Task.sleep(nanoseconds: 80_000_000)
            }
        }

        return nil
    }

    private static func isPreviewCDN(_ url: URL) -> Bool {
        url.host?.lowercased() == "img.kemono.cr"
    }

    private static func download(url: URL, preferDirectSession: Bool) async throws -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        KemonoRequestHeaders.apply(to: &request, baseURL: AppSettings.baseURL)
        if let sessionCookie = AppSettings.sessionCookie {
            request.setValue("session=\(sessionCookie)", forHTTPHeaderField: "Cookie")
        }

        let (data, response): (Data, URLResponse)
        if preferDirectSession {
            (data, response) = try await KemonoURLSessionFactory.shared.data(for: request)
        } else {
            (data, response) = try await MediaRedirectSession.shared.data(for: request)
        }

        guard let http = response as? HTTPURLResponse else { return nil }
        guard (200..<300).contains(http.statusCode), !data.isEmpty else { return nil }
        return data
    }
}

private final class MediaRedirectSession: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = MediaRedirectSession()

    private let lock = NSLock()
    private var blockedTasks = Set<Int>()
    private lazy var session: URLSession = {
        URLSession(configuration: KemonoURLSessionFactory.configuration, delegate: self, delegateQueue: nil)
    }()

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let taskID = lock.withLock { () -> Int in
            blockedTasks.removeAll(keepingCapacity: true)
            return Int.random(in: 1...Int.max)
        }
        _ = taskID
        return try await session.data(for: request)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let urlString = request.url?.absoluteString,
           KemonoURLResolver.isNodeCDN(urlString) || KemonoURLResolver.isUnreliableMirror(urlString) {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }
}
