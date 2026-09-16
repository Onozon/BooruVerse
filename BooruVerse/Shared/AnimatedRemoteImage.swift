import ImageIO
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Decodes GIF / animated WebP / APNG into timed frames. Single-frame files are stills.
enum AnimatedImageDecoder {
    struct Decoded {
        var frames: [CGImage]
        var durations: [Double]
        var still: PlatformImage?

        var isAnimated: Bool { frames.count > 1 }
    }

    static func decode(_ data: Data) -> Decoded? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return nil }

        if count == 1 {
            guard let image = stillImage(from: source, index: 0) else { return nil }
            return Decoded(frames: [], durations: [], still: image)
        }

        var frames: [CGImage] = []
        var durations: [Double] = []
        frames.reserveCapacity(count)
        durations.reserveCapacity(count)

        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            frames.append(frame)
            durations.append(frameDuration(source: source, index: index))
        }

        guard frames.count > 1 else {
            let still = frames.first.flatMap { platformImage(from: $0) } ?? stillImage(from: source, index: 0)
            return Decoded(frames: [], durations: [], still: still)
        }

        return Decoded(frames: frames, durations: durations, still: platformImage(from: frames[0]))
    }

    private static func stillImage(from source: CGImageSource, index: Int) -> PlatformImage? {
        guard let cg = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
        return platformImage(from: cg)
    }

    private static func platformImage(from cg: CGImage) -> PlatformImage {
#if canImport(UIKit)
        UIImage(cgImage: cg)
#else
        NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
#endif
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any] else {
            return 0.1
        }

        let nestedKeys = ["{GIF}", "{PNG}", "{WebP}", "{HEICS}"]
        for nestedKey in nestedKeys {
            guard let dict = properties[nestedKey] as? [String: Any] else { continue }
            if let unclamped = dict["UnclampedDelayTime"] as? Double, unclamped > 0 {
                return unclamped < 0.011 ? 0.1 : unclamped
            }
            if let clamped = dict["DelayTime"] as? Double, clamped > 0 {
                return clamped < 0.011 ? 0.1 : clamped
            }
        }

        return 0.1
    }
}

struct AnimatedFramesView: View {
    let frames: [CGImage]
    let durations: [Double]
    var isActive: Bool = true

    @State private var index = 0

    var body: some View {
        Group {
            if frames.indices.contains(index) {
                Image(decorative: frames[index], scale: 1)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task(id: "\(isActive)-\(frames.count)") {
            guard isActive, frames.count > 1, durations.count == frames.count else { return }
            index = 0
            while !Task.isCancelled {
                let delay = durations[index]
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                index = (index + 1) % frames.count
            }
        }
    }
}

/// Loads `playbackURL` and shows animation when ImageIO reports multiple frames.
struct AnimatedOrStillRemoteImage: View {
    let url: URL
    var previewURL: URL?
    var isActive: Bool = true
    var onLoaded: (() -> Void)?

    @State private var decoded: AnimatedImageDecoder.Decoded?
    @State private var preview: PlatformImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            Color.black
            if let decoded, decoded.isAnimated {
                AnimatedFramesView(frames: decoded.frames, durations: decoded.durations, isActive: isActive)
            } else if let still = decoded?.still ?? preview {
                still.swiftUIImage
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if failed {
                ContentUnavailableView("Image Unavailable", image: AppIcon.photo)
                    .foregroundStyle(.white)
            } else {
                ProgressView()
                    .tint(.white)
            }
        }
        .task(id: url.absoluteString) {
            await load()
        }
    }

    private func load() async {
        failed = false
        decoded = nil

        if let previewURL,
           let cached = await RemoteImageLoaderBridge.cachedImage(
            for: previewURL,
            maxPixelSize: RemoteImageLoaderDefaults.thumbnailPixelSize
           ) {
            preview = cached
        }

        var request = URLRequest(url: url)
        request.setValue("BooruVerse/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 45

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), !data.isEmpty else {
                failed = decoded == nil && preview == nil
                return
            }
            guard let result = AnimatedImageDecoder.decode(data) else {
                failed = preview == nil
                return
            }
            decoded = result
            onLoaded?()
        } catch {
            failed = preview == nil
        }
    }
}
