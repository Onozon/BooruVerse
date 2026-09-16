import AVFoundation
import SwiftUI
import WebKit

/// Loops a remote video. Downloads first (hotlink-protected CDNs), then plays a local file.
/// Native AVPlayer for MP4/MOV; WKWebView only for WebM/MKV, and only while `isActive`.
struct GalleryVideoPlayer: View {
    let url: URL
    var usesNativePlayer: Bool
    var isActive: Bool = true
    @Binding var isMuted: Bool
    var showsMuteButton: Bool = true

    @State private var localURL: URL?
    @State private var failed = false
    @State private var loading = false

    var body: some View {
        ZStack {
            Color.black
            if !isActive {
                ProgressView()
                    .tint(.white)
            } else if failed {
                ContentUnavailableView("Video Unavailable", image: AppIcon.photo)
                    .foregroundStyle(.white)
            } else if let localURL {
                if usesNativePlayer {
                    NativeLoopingVideoView(url: localURL, isMuted: isMuted, isActive: isActive)
                } else {
                    WebLoopingVideoView(url: localURL, isMuted: isMuted, isActive: isActive)
                }
            } else {
                ProgressView()
                    .tint(.white)
            }

            if showsMuteButton, isActive, !failed {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        VideoMuteButton(isMuted: $isMuted)
                    }
                }
                .padding(16)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: "\(isActive)-\(url.absoluteString)") {
            await prepare(isActive: isActive)
        }
        .onDisappear {
            VideoPlaybackSupport.removeFile(localURL)
            localURL = nil
        }
    }

    @MainActor
    private func prepare(isActive: Bool) async {
        guard isActive else { return }
        if localURL != nil { return }
        failed = false
        loading = true
        let file = await VideoPlaybackSupport.downloadToTempFile(from: url)
        guard !Task.isCancelled else { return }
        loading = false
        if let file {
            localURL = file
        } else {
            failed = true
        }
    }
}

enum VideoPlaybackSupport {
    static let userAgent = "BooruVerse/1.0"

    static func httpHeaders(for url: URL) -> [String: String] {
        var headers = ["User-Agent": userAgent]
        if let scheme = url.scheme, let host = url.host {
            headers["Referer"] = "\(scheme)://\(host)/"
        }
        return headers
    }

    static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "webm": "video/webm"
        case "mkv": "video/x-matroska"
        case "mov": "video/quicktime"
        case "m4v": "video/x-m4v"
        default: "video/mp4"
        }
    }

    static func downloadToTempFile(from url: URL) async -> URL? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        for (key, value) in httpHeaders(for: url) {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 120
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        let session = URLSession(configuration: config)

        do {
            let (tempURL, response) = try await session.download(for: request)
            if let http = response as? HTTPURLResponse {
                guard (200..<300).contains(http.statusCode) else { return nil }
                let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                if type.contains("text/html") { return nil }
            }
            let ext = url.pathExtension.isEmpty ? "mp4" : url.pathExtension
            let dest = FileManager.default.temporaryDirectory
                .appendingPathComponent("booru-video-\(UUID().uuidString).\(ext)")
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.moveItem(at: tempURL, to: dest)
            return dest
        } catch {
            return nil
        }
    }

    static func removeFile(_ url: URL?) {
        guard let url, url.isFileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

#if os(iOS)
private struct NativeLoopingVideoView: UIViewRepresentable {
    let url: URL
    var isMuted: Bool
    var isActive: Bool

    func makeUIView(context: Context) -> LoopingPlayerUIView {
        let view = LoopingPlayerUIView()
        view.load(url)
        view.apply(isMuted: isMuted, isActive: isActive)
        return view
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {
        if uiView.loadedURL != url {
            uiView.load(url)
        }
        uiView.apply(isMuted: isMuted, isActive: isActive)
    }

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.tearDown()
    }
}

final class LoopingPlayerUIView: UIView {
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    var loadedURL: URL?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        clipsToBounds = true
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer.addSublayer(playerLayer)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
        if bounds.height > 1, player.timeControlStatus != .playing, player.currentItem?.status == .readyToPlay {
            player.play()
        }
    }

    func load(_ url: URL) {
        loadedURL = url
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            DispatchQueue.main.async { self?.player.play() }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
    }

    func apply(isMuted: Bool, isActive: Bool) {
        player.isMuted = isMuted
        if isActive {
            player.play()
        } else {
            player.pause()
        }
    }

    func tearDown() {
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

private struct WebLoopingVideoView: UIViewRepresentable {
    let url: URL
    var isMuted: Bool
    var isActive: Bool

    func makeCoordinator() -> LocalVideoSchemeHandler {
        LocalVideoSchemeHandler()
    }

    func makeUIView(context: Context) -> WebVideoContainerView {
        context.coordinator.fileURL = url
        let view = WebVideoContainerView(handler: context.coordinator)
        view.load(fileURL: url)
        return view
    }

    func updateUIView(_ uiView: WebVideoContainerView, context: Context) {
        context.coordinator.fileURL = url
        if uiView.loadedURL != url {
            uiView.load(fileURL: url)
        }
        uiView.apply(isMuted: isMuted, isActive: isActive)
    }

    static func dismantleUIView(_ uiView: WebVideoContainerView, coordinator: LocalVideoSchemeHandler) {
        uiView.tearDown()
        coordinator.fileURL = nil
    }
}

final class WebVideoContainerView: UIView {
    private let webView: WKWebView
    var loadedURL: URL?

    init(handler: LocalVideoSchemeHandler) {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = false
        config.setURLSchemeHandler(handler, forURLScheme: LocalVideoSchemeHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: .zero)
        backgroundColor = .black
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layoutSubviews() {
        super.layoutSubviews()
        webView.frame = bounds
    }

    func load(fileURL: URL) {
        loadedURL = fileURL
        let mime = VideoPlaybackSupport.mimeType(for: fileURL)
        webView.loadHTMLString(localVideoHTML(mimeType: mime), baseURL: nil)
    }

    func apply(isMuted: Bool, isActive: Bool) {
        applyVideoJS(webView, isMuted: isMuted, isActive: isActive)
    }

    func tearDown() {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }
}

#elseif os(macOS)
private struct NativeLoopingVideoView: NSViewRepresentable {
    let url: URL
    var isMuted: Bool
    var isActive: Bool

    func makeNSView(context: Context) -> LoopingPlayerNSView {
        let view = LoopingPlayerNSView()
        view.load(url)
        view.apply(isMuted: isMuted, isActive: isActive)
        return view
    }

    func updateNSView(_ nsView: LoopingPlayerNSView, context: Context) {
        if nsView.loadedURL != url {
            nsView.load(url)
        }
        nsView.apply(isMuted: isMuted, isActive: isActive)
    }

    static func dismantleNSView(_ nsView: LoopingPlayerNSView, coordinator: ()) {
        nsView.tearDown()
    }
}

final class LoopingPlayerNSView: NSView {
    private let player = AVPlayer()
    private let playerLayer = AVPlayerLayer()
    var loadedURL: URL?
    private var statusObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
        player.isMuted = true
        player.automaticallyWaitsToMinimizeStalling = true
        player.actionAtItemEnd = .none
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        playerLayer.frame = bounds
        if bounds.height > 1, player.timeControlStatus != .playing, player.currentItem?.status == .readyToPlay {
            player.play()
        }
    }

    func load(_ url: URL) {
        loadedURL = url
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            guard item.status == .readyToPlay else { return }
            DispatchQueue.main.async { self?.player.play() }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.player.seek(to: .zero)
            self?.player.play()
        }
    }

    func apply(isMuted: Bool, isActive: Bool) {
        player.isMuted = isMuted
        if isActive {
            player.play()
        } else {
            player.pause()
        }
    }

    func tearDown() {
        statusObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

private struct WebLoopingVideoView: NSViewRepresentable {
    let url: URL
    var isMuted: Bool
    var isActive: Bool

    func makeCoordinator() -> LocalVideoSchemeHandler {
        LocalVideoSchemeHandler()
    }

    func makeNSView(context: Context) -> WebVideoContainerView {
        context.coordinator.fileURL = url
        let view = WebVideoContainerView(handler: context.coordinator)
        view.load(fileURL: url)
        return view
    }

    func updateNSView(_ nsView: WebVideoContainerView, context: Context) {
        context.coordinator.fileURL = url
        if nsView.loadedURL != url {
            nsView.load(fileURL: url)
        }
        nsView.apply(isMuted: isMuted, isActive: isActive)
    }

    static func dismantleNSView(_ nsView: WebVideoContainerView, coordinator: LocalVideoSchemeHandler) {
        nsView.tearDown()
        coordinator.fileURL = nil
    }
}

final class WebVideoContainerView: NSView {
    private let webView: WKWebView
    var loadedURL: URL?

    init(handler: LocalVideoSchemeHandler) {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.setURLSchemeHandler(handler, forURLScheme: LocalVideoSchemeHandler.scheme)
        webView = WKWebView(frame: .zero, configuration: config)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.cgColor
        webView.setValue(false, forKey: "drawsBackground")
        addSubview(webView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        webView.frame = bounds
    }

    func load(fileURL: URL) {
        loadedURL = fileURL
        let mime = VideoPlaybackSupport.mimeType(for: fileURL)
        webView.loadHTMLString(localVideoHTML(mimeType: mime), baseURL: nil)
    }

    func apply(isMuted: Bool, isActive: Bool) {
        applyVideoJS(webView, isMuted: isMuted, isActive: isActive)
    }

    func tearDown() {
        webView.stopLoading()
        webView.loadHTMLString("", baseURL: nil)
    }
}
#endif

final class LocalVideoSchemeHandler: NSObject, WKURLSchemeHandler {
    static let scheme = "booruvideo"
    var fileURL: URL?

    func webView(_ webView: WKWebView, start urlSchemeTask: WKURLSchemeTask) {
        guard let fileURL else {
            urlSchemeTask.didFailWithError(URLError(.fileDoesNotExist))
            return
        }
        do {
            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            let mime = VideoPlaybackSupport.mimeType(for: fileURL)
            let response = URLResponse(
                url: urlSchemeTask.request.url ?? fileURL,
                mimeType: mime,
                expectedContentLength: data.count,
                textEncodingName: nil
            )
            urlSchemeTask.didReceive(response)
            urlSchemeTask.didReceive(data)
            urlSchemeTask.didFinish()
        } catch {
            urlSchemeTask.didFailWithError(error)
        }
    }

    func webView(_ webView: WKWebView, stop urlSchemeTask: WKURLSchemeTask) {}
}

private func localVideoHTML(mimeType: String) -> String {
    let src = "\(LocalVideoSchemeHandler.scheme)://play"
    return """
    <!DOCTYPE html>
    <html>
    <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1, user-scalable=no">
    <style>
      html, body { margin: 0; padding: 0; background: #000; width: 100%; height: 100%; overflow: hidden; }
      video { width: 100%; height: 100%; object-fit: contain; background: #000; }
    </style>
    </head>
    <body>
    <video id="v" autoplay loop muted playsinline webkit-playsinline>
      <source src="\(src)" type="\(mimeType)">
    </video>
    </body>
    </html>
    """
}

private func applyVideoJS(_ web: WKWebView, isMuted: Bool, isActive: Bool) {
    let muted = isMuted ? "true" : "false"
    let volume = isMuted ? "0" : "1"
    let play = isActive ? "v.play();" : "v.pause();"
    let js = """
    (function() {
      var v = document.getElementById('v');
      if (!v) return;
      v.muted = \(muted);
      v.volume = \(volume);
      \(play)
    })();
    """
    web.evaluateJavaScript(js, completionHandler: nil)
}
