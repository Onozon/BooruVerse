import Foundation
import SwiftUI
import ImageIO

#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#endif

enum RemoteImagePriority: Int, Sendable, Comparable {
    case background = 0
    case visible = 1
    case high = 2

    nonisolated static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    nonisolated func raised(to other: Self) -> Self {
        Self(rawValue: max(rawValue, other.rawValue)) ?? self
    }
}

nonisolated enum RemoteImageLoaderDefaults {
    /// Grid / compact preview decode size.
    static let thumbnailPixelSize = 480
    /// Compact-feed upgrade size (viewer URL, but capped so fewer huge bitmaps stay resident).
    static let feedFullPixelSize = 1_600
    static let previewCacheCountLimit = 360
    static let previewCacheCostLimit = 64 * 1024 * 1024
    static let fullCacheCountLimit = 48
    static let fullCacheCostLimit = 48 * 1024 * 1024
}

actor RemoteImageLoader {
    static let shared = RemoteImageLoader()

    /// Dedicated session for image downloads: fail fast on stalled connections (e.g. HTTP/3
    /// over a VPN) so we can retry over the fallback path instead of hanging on defaults.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60
        config.httpMaximumConnectionsPerHost = 6
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// Preview / thumbnail bitmaps (many, smaller).
    private let previewCache: NSCache<NSString, CacheBox> = {
        let cache = NSCache<NSString, CacheBox>()
        cache.countLimit = RemoteImageLoaderDefaults.previewCacheCountLimit
        cache.totalCostLimit = RemoteImageLoaderDefaults.previewCacheCostLimit
        return cache
    }()

    /// Full / feed-upgrade bitmaps (fewer, larger).
    private let fullCache: NSCache<NSString, CacheBox> = {
        let cache = NSCache<NSString, CacheBox>()
        cache.countLimit = RemoteImageLoaderDefaults.fullCacheCountLimit
        cache.totalCostLimit = RemoteImageLoaderDefaults.fullCacheCostLimit
        return cache
    }()

    private let maxConcurrentDownloads = 6

    private var downloadTasks: [String: DownloadTaskRecord] = [:]
    /// Callers currently awaiting a given download key. When the last one leaves, in-flight work can be cancelled.
    private var loadWaiters: [String: Set<UUID>] = [:]
    private var slotWaiters: [String: [SlotWaiter]] = [:]
    private var slotQueue: [SlotRequest] = []
    private var activeSlotKeys: Set<String> = []
    private var slotSequence: UInt64 = 0
    private var prefetchingKeys: Set<String> = []

    private struct DownloadTaskRecord {
        let id: UUID
        let task: Task<PlatformImage?, Never>
    }

    private struct SlotRequest: Comparable {
        let key: String
        var priority: RemoteImagePriority
        var sequence: UInt64

        static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.priority.rawValue != rhs.priority.rawValue {
                return lhs.priority.rawValue < rhs.priority.rawValue
            }
            return lhs.sequence < rhs.sequence
        }
    }

    private struct SlotWaiter {
        let id: UUID
        let continuation: CheckedContinuation<Void, Never>
    }

    func evict(url: URL?) {
        guard let url else { return }
        let fullKey = cacheKey(for: url, maxPixelSize: nil)
        fullCache.removeObject(forKey: fullKey)
        previewCache.removeObject(forKey: cacheKey(for: url, maxPixelSize: RemoteImageLoaderDefaults.thumbnailPixelSize))
        previewCache.removeObject(forKey: cacheKey(for: url, maxPixelSize: RemoteImageLoaderDefaults.feedFullPixelSize))
        previewCache.removeObject(forKey: fullKey)
    }

    /// Drops decoded bitmaps so inactive tabs don't keep thumbnails resident.
    /// In-flight downloads and URLCache are left alone — reload is cheap from disk/network cache.
    func purgeDecodedImages() {
        previewCache.removeAllObjects()
        fullCache.removeAllObjects()
        GalleryDebug.log("purged decoded image cache")
    }

    func cachedImage(for url: URL?, maxPixelSize: Int? = nil) -> PlatformImage? {
        guard let url else { return nil }
        let key = cacheKey(for: url, maxPixelSize: maxPixelSize)
        if isFullQuality(maxPixelSize) {
            return fullCache.object(forKey: key)?.image
                ?? previewCache.object(forKey: key)?.image
        }
        return previewCache.object(forKey: key)?.image
    }

    nonisolated func prefetch(_ url: URL?, priority: RemoteImagePriority = .background, maxPixelSize: Int? = RemoteImageLoaderDefaults.thumbnailPixelSize) {
        guard let url else { return }
        Task {
            await self.prefetchIfNeeded(url: url, priority: priority, maxPixelSize: maxPixelSize)
        }
    }

    private func prefetchIfNeeded(url: URL, priority: RemoteImagePriority, maxPixelSize: Int?) async {
        let key = taskKey(for: url, maxPixelSize: maxPixelSize)
        if cachedImage(for: url, maxPixelSize: maxPixelSize) != nil { return }
        if downloadTasks[key] != nil { return }
        if prefetchingKeys.contains(key) { return }

        prefetchingKeys.insert(key)
        defer { prefetchingKeys.remove(key) }

        _ = await load(url: url, priority: priority, maxPixelSize: maxPixelSize)
    }

    func boostPriority(for url: URL?, to priority: RemoteImagePriority = .visible, maxPixelSize: Int? = nil) {
        guard let url else { return }
        let key = taskKey(for: url, maxPixelSize: maxPixelSize)
        guard let index = slotQueue.firstIndex(where: { $0.key == key }) else { return }

        slotQueue[index].priority = slotQueue[index].priority.raised(to: priority)
        slotQueue[index].sequence = nextSlotSequence()
        slotQueue.sort(by: >)
        grantSlotsIfNeeded()
    }

    func load(
        url: URL,
        priority: RemoteImagePriority = .visible,
        maxPixelSize: Int? = nil,
        progressHandler: (@Sendable (Double) -> Void)? = nil
    ) async -> PlatformImage? {
        let key = taskKey(for: url, maxPixelSize: maxPixelSize)
        let storageKey = cacheKey(for: url, maxPixelSize: maxPixelSize)

        if let cached = cachedImage(for: url, maxPixelSize: maxPixelSize) {
            GalleryDebug.log("cache hit", url: url)
            return cached
        }

        let waiterID = UUID()
        registerLoadWaiter(key: key, id: waiterID)
        // Full / feed-upgrade loads cancel when the last waiter scrolls away.
        // Small preview thumbs finish in the background so scroll-back stays snappy.
        let cancelWhenAbandoned = isFullQuality(maxPixelSize)

        return await withTaskCancellationHandler {
            let result = await self.awaitDownload(
                url: url,
                key: key,
                storageKey: storageKey,
                priority: priority,
                maxPixelSize: maxPixelSize,
                progressHandler: progressHandler
            )
            self.unregisterLoadWaiter(key: key, id: waiterID, cancelIfAbandoned: false)
            return result
        } onCancel: {
            Task {
                await self.unregisterLoadWaiter(
                    key: key,
                    id: waiterID,
                    cancelIfAbandoned: cancelWhenAbandoned
                )
            }
        }
    }

    private func awaitDownload(
        url: URL,
        key: String,
        storageKey: NSString,
        priority: RemoteImagePriority,
        maxPixelSize: Int?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async -> PlatformImage? {
        if let cached = cachedImage(for: url, maxPixelSize: maxPixelSize) {
            GalleryDebug.log("cache hit", url: url)
            return cached
        }

        if let existing = downloadTasks[key] {
            GalleryDebug.log("await in-flight", url: url)
            return await existing.task.value
        }

        let taskID = UUID()
        let task = Task<PlatformImage?, Never>(priority: .userInitiated) {
            await self.performDownload(
                url: url,
                key: key,
                storageKey: storageKey,
                priority: priority,
                maxPixelSize: maxPixelSize,
                progressHandler: progressHandler
            )
        }
        downloadTasks[key] = DownloadTaskRecord(id: taskID, task: task)

        let result = await task.value
        if downloadTasks[key]?.id == taskID {
            downloadTasks[key] = nil
        }

        if let result {
            store(result, forKey: storageKey, maxPixelSize: maxPixelSize)
            GalleryDebug.log("download ok", url: url)
        } else if Task.isCancelled {
            GalleryDebug.log("download cancelled", url: url)
        } else {
            GalleryDebug.log("download failed", url: url)
        }

        return result
    }

    private func registerLoadWaiter(key: String, id: UUID) {
        loadWaiters[key, default: []].insert(id)
    }

    private func unregisterLoadWaiter(key: String, id: UUID, cancelIfAbandoned: Bool) {
        guard var waiters = loadWaiters[key] else { return }
        waiters.remove(id)
        if waiters.isEmpty {
            loadWaiters[key] = nil
            if cancelIfAbandoned {
                if let record = downloadTasks[key] {
                    GalleryDebug.log("abandon cancel key=\(key)")
                    record.task.cancel()
                }
                slotQueue.removeAll { $0.key == key }
            }
        } else {
            loadWaiters[key] = waiters
        }
    }

    private func performDownload(
        url: URL,
        key: String,
        storageKey: NSString,
        priority: RemoteImagePriority,
        maxPixelSize: Int?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async -> PlatformImage? {
        if Task.isCancelled { return nil }

        await acquireSlot(key: key, priority: priority)

        defer { releaseSlot(key: key) }

        if Task.isCancelled { return nil }

        if let cached = cachedImage(for: url, maxPixelSize: maxPixelSize) {
            return cached
        }

        GalleryDebug.log("download start", url: url)
        return await Self.downloadAndDecode(
            from: url,
            maxPixelSize: maxPixelSize,
            progressHandler: progressHandler
        )
    }

    private func store(_ image: PlatformImage, forKey key: NSString, maxPixelSize: Int?) {
        let box = CacheBox(image: image)
        let cost = Self.cacheCost(for: image)
        if isFullQuality(maxPixelSize) {
            fullCache.setObject(box, forKey: key, cost: cost)
        } else {
            previewCache.setObject(box, forKey: key, cost: cost)
        }
    }

    private func isFullQuality(_ maxPixelSize: Int?) -> Bool {
        maxPixelSize == nil || maxPixelSize == RemoteImageLoaderDefaults.feedFullPixelSize
    }

    private func cacheKey(for url: URL, maxPixelSize: Int?) -> NSString {
        if let maxPixelSize {
            return "\(url.absoluteString)|thumb\(maxPixelSize)" as NSString
        }
        return url.absoluteString as NSString
    }

    private func taskKey(for url: URL, maxPixelSize: Int?) -> String {
        if let maxPixelSize {
            return "\(url.absoluteString)|thumb\(maxPixelSize)"
        }
        return url.absoluteString
    }

    private func acquireSlot(key: String, priority: RemoteImagePriority) async {
        if activeSlotKeys.contains(key) { return }

        if activeSlotKeys.count < maxConcurrentDownloads {
            activeSlotKeys.insert(key)
            return
        }

        let waiterID = UUID()

        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                enqueueSlotRequest(key: key, priority: priority)
                slotWaiters[key, default: []].append(
                    SlotWaiter(id: waiterID, continuation: continuation)
                )
                grantSlotsIfNeeded()
            }
        } onCancel: {
            Task { await self.cancelSlotWait(for: key, waiterID: waiterID) }
        }
    }

    private func enqueueSlotRequest(key: String, priority: RemoteImagePriority) {
        if let index = slotQueue.firstIndex(where: { $0.key == key }) {
            slotQueue[index].priority = slotQueue[index].priority.raised(to: priority)
            slotQueue[index].sequence = nextSlotSequence()
        } else {
            slotQueue.append(
                SlotRequest(key: key, priority: priority, sequence: nextSlotSequence())
            )
        }
        slotQueue.sort(by: >)
    }

    private func cancelSlotWait(for key: String, waiterID: UUID) {
        guard var waiters = slotWaiters[key],
              let index = waiters.firstIndex(where: { $0.id == waiterID }) else { return }

        let waiter = waiters.remove(at: index)
        if waiters.isEmpty {
            slotWaiters[key] = nil
        } else {
            slotWaiters[key] = waiters
        }

        if !activeSlotKeys.contains(key) {
            slotQueue.removeAll { $0.key == key }
        }

        waiter.continuation.resume()
    }

    private func releaseSlot(key: String) {
        activeSlotKeys.remove(key)
        grantSlotsIfNeeded()
    }

    private func grantSlotsIfNeeded() {
        while activeSlotKeys.count < maxConcurrentDownloads {
            guard let index = slotQueue.firstIndex(where: { !(slotWaiters[$0.key]?.isEmpty ?? true) }) else {
                break
            }

            let next = slotQueue.remove(at: index)
            activeSlotKeys.insert(next.key)

            let waiters = slotWaiters.removeValue(forKey: next.key) ?? []
            for waiter in waiters {
                waiter.continuation.resume()
            }
        }
    }

    private func nextSlotSequence() -> UInt64 {
        slotSequence += 1
        return slotSequence
    }

    private static func downloadAndDecode(
        from url: URL,
        maxPixelSize: Int?,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async -> PlatformImage? {
        var request = URLRequest(url: url)
        request.setValue("BooruVerse/1.0", forHTTPHeaderField: "User-Agent")
        // Some CDNs (e.g. Gelbooru) reject hotlinked images with a 302 redirect unless a
        // same-origin Referer is present. Harmless for hosts that don't check it.
        if let scheme = url.scheme, let host = url.host {
            request.setValue("\(scheme)://\(host)/", forHTTPHeaderField: "Referer")
        }

        let data: Data
        if progressHandler == nil {
            guard let fetched = await fetchDataWithRetry(request: request) else {
                return nil
            }
            data = fetched
        } else {
            guard let downloaded = await downloadWithProgress(request: request, progressHandler: progressHandler) else {
                return nil
            }
            data = downloaded
        }

        return await Task.detached(priority: .utility) {
            Self.decodeImageData(data, maxPixelSize: maxPixelSize)
        }.value
    }

    /// Fetches image data, retrying once on transient network errors (timeouts, dropped
    /// connections) that commonly occur when an HTTP/3 connection stalls behind a VPN.
    private static func fetchDataWithRetry(request: URLRequest, attempts: Int = 2) async -> Data? {
        for attempt in 0..<attempts {
            if Task.isCancelled { return nil }
            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                    return nil
                }
                return data
            } catch is CancellationError {
                return nil
            } catch {
                if Task.isCancelled { return nil }
                if attempt < attempts - 1, isTransientNetworkError(error) {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    continue
                }
                return nil
            }
        }
        return nil
    }

    private static func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .networkConnectionLost, .cannotConnectToHost,
             .cannotFindHost, .dnsLookupFailed, .notConnectedToInternet:
            return true
        default:
            return false
        }
    }

    private static func downloadWithProgress(
        request: URLRequest,
        progressHandler: (@Sendable (Double) -> Void)?
    ) async -> Data? {
        // Avoid URLSession.AsyncBytes byte-at-a-time iteration — on large originals
        // that burns CPU with one async suspension per byte. Use a buffered download instead.
        do {
            progressHandler?(0.05)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            if Task.isCancelled { return nil }
            progressHandler?(1)
            return data
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    private static func decodeImageData(_ data: Data, maxPixelSize: Int?) -> PlatformImage? {
        guard data.count > 64 else { return nil }

        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: true]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else {
            return nil
        }

        let imageCount = CGImageSourceGetCount(source)
        guard imageCount > 0 else { return nil }

        // Only run the (expensive, log-spammy) thumbnail scanner when the image is actually
        // larger than the requested size. Otherwise decode the image directly.
        var shouldDownsample = false
        if let maxPixelSize, maxPixelSize > 0 {
            if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int ?? 0
                let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int ?? 0
                shouldDownsample = max(pixelWidth, pixelHeight) > maxPixelSize
            } else {
                // Unknown dimensions: fall back to downsampling to bound memory.
                shouldDownsample = true
            }
        }

        // `ShouldCacheImmediately` forces ImageIO to produce a fully-decoded bitmap on this
        // background thread, so Core Animation never has to decode lazily on the main thread
        // at draw time (the source of scroll stutter and "cannot add handler" spam).
        if shouldDownsample, let maxPixelSize {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
            ]
            if let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) {
                return platformImage(from: thumbnail)
            }
        }

        let decodeOptions: [CFString: Any] = [kCGImageSourceShouldCacheImmediately: true]
        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, decodeOptions as CFDictionary) else {
            return nil
        }

        return platformImage(from: cgImage)
    }

    private static func platformImage(from cgImage: CGImage) -> PlatformImage {
#if canImport(UIKit)
        UIImage(cgImage: cgImage)
#else
        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
#endif
    }

    private static func cacheCost(for image: PlatformImage) -> Int {
        // Prefer raw bitmap byte size. Never use NSImage.tiffRepresentation for cost —
        // that re-encodes the whole image on every cache insert (very expensive on macOS).
#if canImport(UIKit)
        guard let cgImage = image.cgImage else { return 1 }
        return max(cgImage.bytesPerRow * cgImage.height, 1)
#else
        var rect = CGRect(origin: .zero, size: image.size)
        if let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) {
            return max(cgImage.bytesPerRow * cgImage.height, 1)
        }
        // Fallback when no CGImage is available yet (rare for our decode path).
        let pixelCount = max(Int(image.size.width * image.size.height), 1)
        return pixelCount * 4
#endif
    }

    private final class CacheBox: NSObject {
        let image: PlatformImage
        init(image: PlatformImage) { self.image = image }
    }
}

extension PlatformImage {
    var swiftUIImage: Image {
#if canImport(UIKit)
        Image(uiImage: self)
#else
        Image(nsImage: self)
#endif
    }
}

extension BooruPost {
    var aspectRatio: CGFloat {
        guard width > 0, height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }
}

enum RemoteImageLoaderBridge {
    static var defaultThumbnailPixelSize: Int { RemoteImageLoaderDefaults.thumbnailPixelSize }

    static func cachedImage(for url: URL?, maxPixelSize: Int? = nil) async -> PlatformImage? {
        await RemoteImageLoader.shared.cachedImage(for: url, maxPixelSize: maxPixelSize)
    }

    nonisolated static func purgeDecodedImages() {
        Task {
            await RemoteImageLoader.shared.purgeDecodedImages()
        }
    }

    static func load(
        url: URL,
        priority: RemoteImagePriority = .visible,
        maxPixelSize: Int? = nil,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async -> PlatformImage? {
        await RemoteImageLoader.shared.load(
            url: url,
            priority: priority,
            maxPixelSize: maxPixelSize,
            progressHandler: progress
        )
    }

    nonisolated static func prefetch(
        _ url: URL?,
        priority: RemoteImagePriority = .background,
        maxPixelSize: Int? = RemoteImageLoaderDefaults.thumbnailPixelSize
    ) {
        RemoteImageLoader.shared.prefetch(url, priority: priority, maxPixelSize: maxPixelSize)
    }

    nonisolated static func boostPriority(
        for url: URL?,
        to priority: RemoteImagePriority = .visible,
        maxPixelSize: Int? = RemoteImageLoaderDefaults.thumbnailPixelSize
    ) {
        guard let url else { return }
        Task {
            await RemoteImageLoader.shared.boostPriority(for: url, to: priority, maxPixelSize: maxPixelSize)
        }
    }
}
