import SwiftUI

/// Window / container width used to drive Mac phone-like chrome.
private struct LayoutWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct CompactLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// `true` when the window is narrow enough for iPhone-like chrome (Mac only).
    var compactLayout: Bool {
        get { self[CompactLayoutKey.self] }
        set { self[CompactLayoutKey.self] = newValue }
    }
}

#if os(macOS)
/// On macOS, system `horizontalSizeClass` stays `.regular` at any width.
/// Measure the window and publish both `.compact` size class and `compactLayout`.
private struct AdaptiveHorizontalSizeClassModifier: ViewModifier {
    var compactBelow: CGFloat = 700
    @State private var width: CGFloat = 0

    private var isCompact: Bool {
        width > 0 && width < compactBelow
    }

    func body(content: Content) -> some View {
        content
            .background {
                GeometryReader { proxy in
                    Color.clear
                        .preference(key: LayoutWidthKey.self, value: proxy.size.width)
                }
                .ignoresSafeArea()
            }
            .onPreferenceChange(LayoutWidthKey.self) { width = $0 }
            .environment(\.horizontalSizeClass, isCompact ? .compact : .regular)
            .environment(\.compactLayout, isCompact)
    }
}
#endif

extension View {
    /// Enables iPhone-like layout when the Mac window is narrow.
    @ViewBuilder
    func adaptiveHorizontalSizeClass(compactBelow: CGFloat = 700) -> some View {
#if os(macOS)
        modifier(AdaptiveHorizontalSizeClassModifier(compactBelow: compactBelow))
#else
        self
#endif
    }
}
