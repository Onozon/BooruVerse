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
    case photosDenied
    case photosFailed
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingImage: "Could not download the image."
        case .photosDenied: "Photo library access was denied."
        case .photosFailed: "Could not save to Photos."
        case .encodingFailed: "Could not encode the image."
        }
    }
}

enum PostImageSaver {
    static func downloadURL(for post: BooruPost) -> URL? {
        post.fileURL ?? post.sampleURL ?? post.viewerURL
    }

    static func imageData(for post: BooruPost) async throws -> Data {
        guard let url = downloadURL(for: post),
              let image = await RemoteImageLoaderBridge.load(url: url) else {
            throw PostImageSaverError.missingImage
        }
        guard let data = encode(image, ext: post.fileExt) else {
            throw PostImageSaverError.encodingFailed
        }
        return data
    }

    static func saveToPhotos(post: BooruPost) async throws {
        let data = try await imageData(for: post)
        try await saveDataToPhotos(data)
    }

    static func defaultFilename(for post: BooruPost) -> String {
        let ext = normalizedExtension(post.fileExt)
        return "yande.re-\(post.id).\(ext)"
    }

    static func contentType(for post: BooruPost) -> UTType {
        UTType(filenameExtension: normalizedExtension(post.fileExt)) ?? .image
    }

    private static func normalizedExtension(_ ext: String) -> String {
        let trimmed = ext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.isEmpty ? "jpg" : trimmed
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

    private static func saveDataToPhotos(_ data: Data) async throws {
#if canImport(Photos)
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw PostImageSaverError.photosDenied
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges {
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
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
