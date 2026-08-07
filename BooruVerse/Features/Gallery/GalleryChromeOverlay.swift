import SwiftUI

struct GalleryBottomChrome: View {
    @Bindable var model: BrowseViewModel
    let post: BooruPost
    let tagGroups: [BooruTagGroup]
    let onAddTag: (String) -> Void
    let onExport: () -> Void
    let onSaveError: (String) -> Void

    @State private var panelExpansion: CGFloat = 0
    @State private var tagsResetToken = 0

    private let tagsCollapsedHeight: CGFloat = 88
    private let actionBarHeight: CGFloat = 64
    private let maxTagsExpandedHeight: CGFloat = 300
    private let gradientFadeHeight: CGFloat = 56

    private var maxPanelExpansion: CGFloat {
        maxTagsExpandedHeight - tagsCollapsedHeight
    }

    private var tagsVisibleHeight: CGFloat {
        tagsCollapsedHeight + panelExpansion
    }

    private var totalChromeHeight: CGFloat {
        tagsVisibleHeight + actionBarHeight
    }

    var body: some View {
        VStack(spacing: 0) {
            GalleryTagsScrollView(
                groups: tagGroups,
                onAddTag: onAddTag,
                collapsedHeight: tagsCollapsedHeight,
                maxExpansion: maxPanelExpansion,
                resetToken: tagsResetToken,
                panelExpansion: $panelExpansion
            )
            .frame(height: tagsVisibleHeight)
            .contentShape(Rectangle())
            .clipped()

            PostImageActionBar(
                model: model,
                post: post,
                onExport: onExport,
                onSaveError: onSaveError,
                usesLightContent: true
            )
            .frame(height: actionBarHeight)
        }
        .background(alignment: .bottom) {
            chromeBackdrop
                .ignoresSafeArea(edges: .bottom)
        }
        .safeAreaPadding(.bottom)
        .onChange(of: post.id) { _, _ in
            tagsResetToken += 1
            panelExpansion = 0
        }
    }

    private var chromeBackdrop: some View {
        VStack(spacing: 0) {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.3), location: 0.22),
                    .init(color: .black.opacity(0.62), location: 0.52),
                    .init(color: .black.opacity(0.88), location: 0.82),
                    .init(color: .black.opacity(0.94), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: totalChromeHeight + gradientFadeHeight)

            Color.black.opacity(0.94)
        }
        .frame(maxWidth: .infinity)
    }
}

struct GalleryCloseButton: View {
    let onClose: () -> Void

    var body: some View {
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(.black.opacity(0.45), in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .padding(.horizontal, 16)
        .safeAreaPadding(.top, 8)
    }
}
