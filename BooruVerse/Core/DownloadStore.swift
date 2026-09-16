import Foundation

#if canImport(Photos)
import Photos
#endif

/// Queued original-quality saves to Photos or the filesystem.
@MainActor
@Observable
final class DownloadStore {
    static let shared = DownloadStore()

    enum Destination: Equatable {
        case photos
        case directory(URL)
    }

    enum Status: Equatable {
        case queued
        case running
        case failed
        case done
    }

    struct Job: Identifiable, Equatable {
        let id: String
        let post: BooruPost
        var destination: Destination
        var status: Status
        /// Indeterminate while fetching; 1 when finished successfully.
        var progress: Double
        var error: String?
        var destPath: String?
    }

    private(set) var jobs: [Job] = []
    /// IDs currently queued or running (not done/failed). Allows re-enqueue after success.
    private var activeIDs: Set<String> = []
    private var runningCount = 0
    private var allSucceeded = false
    private var hideTask: Task<Void, Never>?
    /// Balanced `startAccessingSecurityScopedResource` counts keyed by path.
    private var securityScopeCounts: [String: (url: URL, count: Int)] = [:]

    private let maxConcurrent = 4

    var busy: Bool { runningCount > 0 }
    var hasFailed: Bool { jobs.contains { $0.status == .failed } }
    var visible: Bool {
        !jobs.isEmpty && (busy || hasFailed || allSucceeded)
    }

    private init() {}

    func enqueue(_ posts: [BooruPost], destination: Destination) {
        guard !posts.isEmpty else { return }
        hideTask?.cancel()
        hideTask = nil
        allSucceeded = false

        var resolvedDestination = destination
        if case .directory(let url) = destination {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            resolvedDestination = .directory(url)
        }

        var added: [Job] = []
        for post in posts {
            let id = post.globalID
            if activeIDs.contains(id) { continue }
            activeIDs.insert(id)
            if case .directory(let url) = resolvedDestination {
                retainSecurityScope(for: url)
            }
            added.append(
                Job(
                    id: id,
                    post: post,
                    destination: resolvedDestination,
                    status: .queued,
                    progress: 0,
                    error: nil,
                    destPath: {
                        if case .directory(let url) = resolvedDestination {
                            return url.appendingPathComponent(Self.fileName(for: post)).path
                        }
                        return nil
                    }()
                )
            )
        }
        guard !added.isEmpty else { return }
        jobs.append(contentsOf: added)
        pump()
    }

    func retryFailed() {
        var any = false
        for index in jobs.indices where jobs[index].status == .failed {
            if case .directory(let url) = jobs[index].destination {
                retainSecurityScope(for: url)
            }
            activeIDs.insert(jobs[index].id)
            jobs[index].status = .queued
            jobs[index].progress = 0
            jobs[index].error = nil
            any = true
        }
        guard any else { return }
        hideTask?.cancel()
        hideTask = nil
        allSucceeded = false
        pump()
    }

    private func pump() {
        while runningCount < maxConcurrent {
            guard let index = jobs.firstIndex(where: { $0.status == .queued }) else { break }
            start(at: index)
        }
        refreshCompletion()
    }

    private func start(at index: Int) {
        jobs[index].status = .running
        // Indeterminate fetch — UI uses ProgressView() when progress <= 0.
        jobs[index].progress = 0
        runningCount += 1
        let jobID = jobs[index].id
        let post = jobs[index].post
        let destination = jobs[index].destination
        let destPath = jobs[index].destPath

        Task {
            do {
                switch destination {
                case .photos:
                    try await PostImageSaver.saveOriginalToPhotos(post: post)
                case .directory:
                    let data = try await PostImageSaver.originalImageData(for: post)
                    guard let destPath else { throw PostImageSaverError.missingImage }
                    let url = URL(fileURLWithPath: destPath)
                    try data.write(to: url, options: .atomic)
                }
                finish(jobID: jobID, success: true, error: nil)
            } catch {
                finish(jobID: jobID, success: false, error: error.localizedDescription)
            }
        }
    }

    private func finish(jobID: String, success: Bool, error: String?) {
        guard let index = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        let destination = jobs[index].destination
        runningCount = max(0, runningCount - 1)
        activeIDs.remove(jobID)
        if success {
            jobs[index].status = .done
            jobs[index].progress = 1
            jobs[index].error = nil
        } else {
            jobs[index].status = .failed
            jobs[index].progress = 0
            jobs[index].error = error ?? "Download failed"
        }
        if case .directory(let url) = destination {
            releaseSecurityScope(for: url)
        }
        pump()
    }

    private func refreshCompletion() {
        guard runningCount == 0 else {
            allSucceeded = false
            hideTask?.cancel()
            hideTask = nil
            return
        }
        guard !jobs.isEmpty else {
            allSucceeded = false
            return
        }
        if jobs.contains(where: { $0.status == .failed }) {
            allSucceeded = false
            let remaining = jobs.filter { $0.status == .failed }
            // Failed jobs are idle — allow re-enqueue; Retry re-inserts into activeIDs.
            activeIDs.removeAll()
            jobs = remaining
            return
        }
        guard jobs.allSatisfy({ $0.status == .done }) else { return }
        allSucceeded = true
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            clearFinishedIfIdle()
        }
    }

    private func clearFinishedIfIdle() {
        guard !busy, !hasFailed else { return }
        jobs.removeAll()
        activeIDs.removeAll()
        allSucceeded = false
    }

    private func retainSecurityScope(for url: URL) {
        let key = url.path
        if var entry = securityScopeCounts[key] {
            entry.count += 1
            securityScopeCounts[key] = entry
            return
        }
        _ = url.startAccessingSecurityScopedResource()
        securityScopeCounts[key] = (url, 1)
    }

    private func releaseSecurityScope(for url: URL) {
        let key = url.path
        guard var entry = securityScopeCounts[key] else { return }
        entry.count -= 1
        if entry.count <= 0 {
            entry.url.stopAccessingSecurityScopedResource()
            securityScopeCounts.removeValue(forKey: key)
        } else {
            securityScopeCounts[key] = entry
        }
    }

    static func fileName(for post: BooruPost) -> String {
        PostImageSaver.defaultFilename(for: post)
    }
}
