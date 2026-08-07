import SwiftUI

extension View {
    func searchActionToolbar(isEnabled: Bool, isLoading: Bool, action: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItem(placement: .primaryAction) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button("Search", action: action)
                        .disabled(!isEnabled)
                }
            }
        }
    }
}
