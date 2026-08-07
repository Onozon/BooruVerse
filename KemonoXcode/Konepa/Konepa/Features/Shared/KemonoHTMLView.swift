import SwiftUI
import WebKit

struct KemonoHTMLView: View {
    let html: String

    var body: some View {
        KemonoHTMLWebView(html: wrappedHTML)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
    }

    private var wrappedHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
          body {
            font-family: -apple-system, BlinkMacSystemFont, sans-serif;
            font-size: 16px;
            line-height: 1.5;
            color: #111;
            margin: 0;
            padding: 0;
            word-wrap: break-word;
          }
          img { max-width: 100%; height: auto; }
          a { color: #007aff; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }
}

#if os(iOS)
private struct KemonoHTMLWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: AppSettings.baseURL)
    }
}
#else
private struct KemonoHTMLWebView: NSViewRepresentable {
    let html: String

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        webView.loadHTMLString(html, baseURL: AppSettings.baseURL)
    }
}
#endif
