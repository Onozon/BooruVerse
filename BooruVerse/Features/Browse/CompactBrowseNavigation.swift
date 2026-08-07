import SwiftUI

struct CompactSidebarDismissGesture: ViewModifier {
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .compact {
            content.simultaneousGesture(dismissGesture)
        } else {
            content
        }
    }

    private var dismissGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), horizontal < -60 else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    preferredCompactColumn = .detail
                }
            }
    }
}

struct CompactSidebarPresentGesture: ViewModifier {
    @Binding var preferredCompactColumn: NavigationSplitViewColumn
    let isEnabled: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    func body(content: Content) -> some View {
        if horizontalSizeClass == .compact, isEnabled {
            content.simultaneousGesture(presentGesture)
        } else {
            content
        }
    }

    private var presentGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                guard abs(horizontal) > abs(vertical), horizontal > 60 else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    preferredCompactColumn = .sidebar
                }
            }
    }
}

extension View {
    @ViewBuilder
    func hideSystemSidebarToggle(_ hidden: Bool) -> some View {
        if hidden {
            toolbar(removing: .sidebarToggle)
        } else {
            self
        }
    }
}
