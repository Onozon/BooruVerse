import Foundation
import SwiftData

enum CatalogSyncPhase: Sendable {
    case idle
    case downloading
    case importing
}

@MainActor
@Observable
final class CatalogSyncEngine {
    static let maxAttempts = 6

    private(set) var isSyncing = false
    private(set) var phase: CatalogSyncPhase = .idle
    private(set) var downloadedCount = 0
    private(set) var savedCount = 0
    private(set) var attempt = 0
    private(set) var errorMessage: String?

    private let modelContainer: ModelContainer
    private let mainContext: ModelContext
    private let apiClient: KemonoAPIClient

    init(modelContainer: ModelContainer, mainContext: ModelContext, apiClient: KemonoAPIClient? = nil) {
        self.modelContainer = modelContainer
        self.mainContext = mainContext
        self.apiClient = apiClient ?? KemonoAPIClient()
    }

    func syncCatalog() async {
        guard !isSyncing else { return }

        isSyncing = true
        phase = .downloading
        downloadedCount = 0
        savedCount = (try? AuthorRepository.count(in: mainContext)) ?? 0
        attempt = 0
        errorMessage = nil

        let state = AuthorRepository.catalogSyncState(in: mainContext)
        state.lastError = nil

        defer {
            isSyncing = false
            phase = .idle
            savedCount = (try? AuthorRepository.count(in: mainContext)) ?? savedCount
        }

        for attemptIndex in 1...Self.maxAttempts {
            attempt = attemptIndex

            do {
                phase = .downloading
                let artists = try await apiClient.fetchCreatorCatalog()
                downloadedCount = artists.count

                phase = .importing
                savedCount = 0

                try await Task.detached(priority: .userInitiated) {
                    try await CatalogImporter.importCatalog(artists, container: self.modelContainer) { processed in
                        await MainActor.run {
                            self.savedCount = processed
                        }
                    }
                }.value

                let dbCount = try AuthorRepository.count(in: mainContext)
                savedCount = dbCount
                state.lastSyncedAt = .now
                state.authorCount = dbCount
                state.lastError = nil
                try? mainContext.save()
                return
            } catch is CancellationError {
                return
            } catch {
                let dbCount = (try? AuthorRepository.count(in: mainContext)) ?? savedCount
                savedCount = dbCount
                state.authorCount = dbCount

                if attemptIndex == Self.maxAttempts || !Self.shouldRetry(error) {
                    errorMessage = Self.failureMessage(error: error, saved: dbCount, attempt: attemptIndex)
                    state.lastError = errorMessage
                    try? mainContext.save()
                    return
                }

                phase = .downloading
                let delay = UInt64(pow(2.0, Double(attemptIndex - 1))) * 1_500_000_000
                try? await Task.sleep(nanoseconds: delay)
            }
        }
    }

    private static func shouldRetry(_ error: Error) -> Bool {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .networkConnectionLost, .cannotConnectToHost,
                 .secureConnectionFailed, .serverCertificateUntrusted,
                 .clientCertificateRejected, .dnsLookupFailed, .notConnectedToInternet:
                return true
            default:
                return false
            }
        }

        if let apiError = error as? KemonoAPIError {
            switch apiError {
            case .network(let urlError):
                return shouldRetry(urlError)
            case .httpStatus(429, _), .httpStatus(502, _), .httpStatus(503, _), .httpStatus(504, _):
                return true
            default:
                return false
            }
        }

        return false
    }

    private static func failureMessage(error: Error, saved: Int, attempt: Int) -> String {
        let base: String
        if let urlError = error as? URLError, urlError.code == .secureConnectionFailed {
            base = "TLS connection dropped. Saved \(saved) authors."
        } else {
            base = "Sync failed after \(attempt) attempt(s). Saved \(saved) authors."
        }
        return "\(base) Tap Sync again to continue — existing records are kept."
    }
}
