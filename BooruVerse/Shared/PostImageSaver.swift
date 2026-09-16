import Foundation
import SwiftUI
import UniformTypeIdentifiers

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
#if canImport(Photos)
import Photos
#endif

enum PostImageSaverError: LocalizedError {
    case missingImage
    case missingOriginal
    case photosDenied
    case photosFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingImage: "Could not download the image."
        case .missingOriginal: "Original file URL is missing for this post."
        case .photosDenied: "Photo library access was denied."
        case .photosFailed: "Could not save to Photos."
        case .encodingFailed: "Could not encode the image."
        }
    }
}

enum PostImageSaver {
    /// Original file URL only (plan: always original quality — no sample/viewer fallback).
    static func originalDownloadURL(for post: BooruPost) -> URL? {
        post.fileURL
    }

    static func downloadURL(for post: BooruPost) -> URL? {
        originalDownloadURL(for: post)
    }

    static func originalImageData(for post: BooruPost) async throws -> Data {
        guard let url = originalDownloadURL(for: post) else {
            throw PostImageSaverError.missingOriginal
        }
        // Prefer raw bytes when possible so we keep the original file, not a re-encode.
        if let (data, _) = try? await URLSession.shared.data(from: url), !data.isEmpty {
            return data
        }
        guard let image = await RemoteImageLoaderBridge.load(url: url, priority: .high, maxPixelSize: nil) else {
            throw PostImageSaverError.missingImage
        }
        guard let data = encode(image, ext: post.fileExt) else {
            throw PostImageSaverError.encodingFailed
        }
        return data
    }

    static func imageData(for post: BooruPost) async throws -> Data {
        try await originalImageData(for: post)
    }

    static func saveToPhotos(post: BooruPost) async throws {
        try await saveOriginalToPhotos(post: post)
    }

    static func saveOriginalToPhotos(post: BooruPost) async throws {
        let data = try await originalImageData(for: post)
        try await saveDataToPhotos(data, fileExt: post.fileExt)
    }

    static func defaultFilename(for post: BooruPost) -> String {
        var ext = post.fileExt.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ext.isEmpty { ext = "jpg" }
        return "\(post.serverID)_\(post.id).\(ext)".replacingOccurrences(of: "/", with: "_")
    }

    static func contentType(for post: BooruPost) -> UTType {
        UTType(filenameExtension: normalizedExtension(post.fileExt)) ?? .image
    }

    /// Request Photos add access once; throws `photosDenied` if unavailable.
    static func ensurePhotosAccess() async throws {
#if canImport(Photos)
        let current = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        switch current {
        case .authorized, .limited:
            return
        case .notDetermined:
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else {
                throw PostImageSaverError.photosDenied
            }
        default:
            throw PostImageSaverError.photosDenied
        }
#else
        throw PostImageSaverError.photosFailed
#endif
    }

    private static func normalizedExtension(_ ext: String) -> String {
        let trimmed = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "jpg" : trimmed
    }

    private static func isVideoExtension(_ ext: String) -> Bool {
        BooruPost.videoExtensions.contains(normalizedExtension(ext))
    }

    private static func encode(_ image: PlatformImage, ext: String) -> Data? {
        let normalized = normalizedExtension(ext)
        switch normalized {
        case "jpg", "jpeg":
#if canImport(UIKit)
            return image.jpegData(compressionQuality: 0.95)
#else
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
#endif
        case "png":
#if canImport(UIKit)
            return image.pngData()
#else
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .png, properties: [:])
#endif
        default:
#if canImport(UIKit)
            return image.jpegData(compressionQuality: 0.95)
#else
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff) else { return nil }
            return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
#endif
        }
    }

    private static func saveDataToPhotos(_ data: Data, fileExt: String) async throws {
#if canImport(Photos)
        try await ensurePhotosAccess()

        let resourceType: PHAssetResourceType = isVideoExtension(fileExt) ? .video : .photo

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: resourceType, data: data, options: nil)
            } completionHandler: { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: error ?? PostImageSaverError.photosFailed)
                }
            }
        }
#else
        throw PostImageSaverError.photosFailed
#endif
    }
}

struct SavedImageDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.image, .jpeg, .png, .data] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw PostImageSaverError.missingImage
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
