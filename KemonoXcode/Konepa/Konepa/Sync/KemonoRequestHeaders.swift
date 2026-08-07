import Foundation

enum KemonoRequestHeaders {
    static func userAgent() -> String {
#if os(iOS)
        "Mozilla/5.0 (iPad; CPU OS 17_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.6 Mobile/15E148 Safari/604.1"
#else
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
#endif
    }

    static func apply(to request: inout URLRequest, baseURL: URL) {
        request.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        request.setValue("text/css", forHTTPHeaderField: "Accept")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")

#if os(macOS)
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("1", forHTTPHeaderField: "Upgrade-Insecure-Requests")
        request.setValue("1", forHTTPHeaderField: "DNT")
        request.setValue("max-age=0", forHTTPHeaderField: "Cache-Control")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("none", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("?1", forHTTPHeaderField: "Sec-Fetch-User")
        request.setValue(
            #""Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120""#,
            forHTTPHeaderField: "sec-ch-ua"
        )
        request.setValue("?0", forHTTPHeaderField: "sec-ch-ua-mobile")
        request.setValue(#""macOS""#, forHTTPHeaderField: "sec-ch-ua-platform")
#endif
    }
}
