import SwiftUI

/// Horizontal thumbnails for parent/child versions of the current post.
struct PostFamilyStrip: View {
    let posts: [BooruPost]
    let selectedID: String
    var usesLightContent = false
    let onSelect: (BooruPost) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(posts, id: \.globalID) { post in
                    Button {
                        onSelect(post)
                    } label: {
                        RemoteThumbnail(url: post.previewURL, contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(
                                        post.globalID == selectedID
                                            ? (usesLightContent ? Color.white : Color.accentColor)
                                            : Color.primary.opacity(0.12),
                                        lineWidth: post.globalID == selectedID ? 2 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Version #\(post.id)")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Other versions")
    }
}

enum AppSidebarKind {
    case browse
    case favorites
}

/// Shared with `MacTitlebarTabBar` so chrome chips match the tab switcher.
enum ChromeBarMetrics {
    static var height: CGFloat {
#if os(iOS)
        48
#else
        32
#endif
    }

    static var width: CGFloat { height }
}

/// Frosted chip so titlebar / tab-bar icons stay readable over light content.
private struct ChromeIconBubble: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(width: ChromeBarMetrics.width, height: ChromeBarMetrics.height)
            .contentShape(Capsule())
            .background { bubble }
    }

    @ViewBuilder
    private var bubble: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            Capsule()
                .fill(.clear)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .strokeBorder(Color.primary.opacity(0.14), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.12), radius: 2, y: 1)
        }
    }
}

extension View {
    fileprivate func chromeIconBubble() -> some View {
        modifier(ChromeIconBubble())
    }
}

struct SidebarToggleButton: View {
    var kind: AppSidebarKind = .browse

    @Environment(AppSettingsStore.self) private var settings

    private var isVisible: Bool {
        switch kind {
        case .browse: settings.showsBrowseSidebar
        case .favorites: settings.showsFavoritesSidebar
        }
    }

    var body: some View {
        Button {
            switch kind {
            case .browse: settings.showsBrowseSidebar.toggle()
            case .favorites: settings.showsFavoritesSidebar.toggle()
            }
        } label: {
            Label(isVisible ? "Hide Sidebar" : "Show Sidebar", appIcon: AppIcon.sidebar)
                .labelStyle(.iconOnly)
                .chromeIconBubble()
        }
        .buttonStyle(.plain)
        .help("Toggle Sidebar")
        .accessibilityLabel(isVisible ? "Hide Sidebar" : "Show Sidebar")
    }
}

struct RandomPostButton: View {
    @Bindable var model: BrowseViewModel
    /// Compact nav bars already wrap items in a system capsule.
    var usesChromeBubble = true

    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PeekCoordinator.self) private var peek

    var body: some View {
        let button = Button {
            Task { await openRandom() }
        } label: {
            if usesChromeBubble {
                Group {
                    if model.isLoadingRandom {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(AppIcon.dice)
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                    }
                }
                .chromeIconBubble()
            } else if model.isLoadingRandom {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("Random post", appIcon: AppIcon.dice)
            }
        }
        .disabled(model.isLoadingRandom || !model.servers.contains { $0.apiFlavor.supportsRandomPosts })
        .help("Random post")
        .accessibilityLabel("Random post")

        if usesChromeBubble {
            button.buttonStyle(.plain)
        } else {
            button
        }
    }

    private func openRandom() async {
        peek.dismiss()
        guard let post = await model.fetchRandomPost() else { return }
        gallery.open(model: model, posts: [post], selectedPostID: post.globalID)
    }
}

/// Sidebar + optional random, as two separate controls.
struct RegularBrowseLeadingButtons: View {
    var sidebar: AppSidebarKind = .browse
    var model: BrowseViewModel?
    var showsRandom = true

    var body: some View {
        HStack(spacing: 8) {
            SidebarToggleButton(kind: sidebar)
            if showsRandom, let model {
                RandomPostButton(model: model)
            }
        }
    }
}

struct RegularBrowseTrailingButtons: View {
    @Bindable var model: BrowseViewModel

    var body: some View {
        HStack(spacing: 10) {
            if model.isLoading || model.isLoadingMore {
                ProgressView()
                    .controlSize(.small)
            }
            SelectionChromeView()
            RefreshPostsButton(model: model)
        }
    }
}

struct RefreshPostsButton: View {
    @Bindable var model: BrowseViewModel

    var body: some View {
        Button {
            Task { await model.refreshPosts() }
        } label: {
            Label("Refresh", appIcon: AppIcon.refresh)
                .labelStyle(.iconOnly)
                .chromeIconBubble()
        }
        .buttonStyle(.plain)
        .disabled(model.isLoading)
        .help("Refresh")
        .accessibilityLabel("Refresh")
    }
}
