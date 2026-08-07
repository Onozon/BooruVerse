import SwiftUI

@main
struct BooruVerseApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .adaptiveHorizontalSizeClass()
#if os(macOS)
                // Allow phone-like narrow windows; compact layout kicks in below ~700pt.
                .frame(minWidth: 360, minHeight: 480)
#endif
        }
#if os(macOS)
        .defaultSize(width: 1100, height: 760)
#endif
    }
}
