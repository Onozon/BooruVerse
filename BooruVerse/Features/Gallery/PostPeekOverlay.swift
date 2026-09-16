import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct PostPeekOverlay: View {
    @Bindable var model: BrowseViewModel
    let post: BooruPost
    /// Browse tag set used for toggle + selected chip styling (may differ from `model` when peeking Feed/Favorites).
    @Bindable var browseModel: BrowseViewModel
    let onToggleTag: (String) async -> Void
    let onDismiss: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(ServerStore.self) private var servers
    @Environment(GalleryCoordinator.self) private var gallery
    @Environment(PostFamilyStore.self) private var families

    @State private var appeared = false
    @State private var peekMuted = true

    private var tagGroups: [BooruTagGroup] {
        model.postTagGroups(for: post)
    }

    private var selectedBrowseTags: Set<String> {
        Set(browseModel.tagQuery.tags)
    }

    @Environment(SelectionStore.self) private var selection

    private var serverDisplayName: String {
        servers.server(host: post.serverID)?.displayName ?? post.serverID
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                    .opacity(appeared ? 0.45 : 0)
                    .ignoresSafeArea()
                    .onTapGesture(perform: dismiss)

                card(in: geometry.size)
                    .scaleEffect(appeared ? 1 : 0.9, anchor: .center)
                    .opacity(appeared ? 1 : 0)
            }
        }
        .ignoresSafeArea()
        .onAppear {
            model.resolvePostTags(for: post)
            peekHaptic()
            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                appeared = true
            }
            Task { await families.loadIfNeeded(post: post) }
        }
    }

    @ViewBuilder
    private func card(in size: CGSize) -> some View {
        let cardWidth = min(size.width - 32, horizontalSizeClass == .compact ? 360 : 640)
        let cardHeight = min(size.height * 0.78, horizontalSizeClass == .compact ? 560 : 480)
        let headerHeight: CGFloat = 36
        let actionsHeight: CGFloat = 56
        let familyExtra: CGFloat = families.cachedFamily(for: post).count > 1 ? 68 : 0
        let imageHeight = (cardHeight - headerHeight - actionsHeight - familyExtra) * 0.52
        let tagsHeight = cardHeight - imageHeight - headerHeight - actionsHeight - familyExtra

        Group {
            if horizontalSizeClass == .compact {
                compactCard(
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    imageHeight: imageHeight,
                    headerHeight: headerHeight,
                    tagsHeight: tagsHeight,
                    actionsHeight: actionsHeight
                )
            } else {
                regularCard(
                    cardWidth: cardWidth,
                    cardHeight: cardHeight,
                    imageHeight: imageHeight,
                    headerHeight: headerHeight,
                    tagsHeight: tagsHeight,
                    actionsHeight: actionsHeight
                )
            }
        }
        .frame(width: cardWidth, height: cardHeight)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.28), radius: 24, y: 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func compactCard(
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        imageHeight: CGFloat,
        headerHeight: CGFloat,
        tagsHeight: CGFloat,
        actionsHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            peekImage
                .frame(width: cardWidth, height: imageHeight)

            peekFamilyStrip

            tagsHeader
                .frame(height: headerHeight)

            PostTagsListView(
                groups: tagGroups,
                selectedTags: selectedBrowseTags,
                onToggleTag: toggleTag
            )
                .frame(height: tagsHeight)

            Divider()

            PostImageActionBar(
                model: model,
                post: post
            )
            .frame(height: actionsHeight)
            .contextMenu {
                PostImageContextMenu(model: model, post: post)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    private func regularCard(
        cardWidth: CGFloat,
        cardHeight: CGFloat,
        imageHeight: CGFloat,
        headerHeight: CGFloat,
        tagsHeight: CGFloat,
        actionsHeight: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    peekImage
                        .frame(width: cardWidth * 0.48, height: cardHeight - actionsHeight - peekFamilyHeight)
                    peekFamilyStrip
                }

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    tagsHeader
                        .frame(height: headerHeight)

                    PostTagsListView(
                        groups: tagGroups,
                        selectedTags: selectedBrowseTags,
                        onToggleTag: toggleTag
                    )
                }
                .frame(width: cardWidth * 0.52 - 1)
            }

            Divider()

            PostImageActionBar(
                model: model,
                post: post
            )
            .frame(height: actionsHeight)
            .contextMenu {
                PostImageContextMenu(model: model, post: post)
            }
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    private var peekImage: some View {
        Group {
            if post.isVideo, let url = post.playbackURL {
                GalleryVideoPlayer(
                    url: url,
                    usesNativePlayer: post.usesNativeAVPlayer,
                    isActive: true,
                    isMuted: $peekMuted,
                    showsMuteButton: true
                )
            } else if post.prefersAnimatedOriginal, let url = post.playbackURL {
                AnimatedOrStillRemoteImage(url: url, previewURL: post.previewURL, isActive: true)
            } else {
                RemoteThumbnail(url: post.previewURL, contentMode: .fit)
            }
        }
        .aspectRatio(post.aspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .topLeading) {
            // Always available so touch users can start a selection without ⌘.
            SelectionCheckboxButton(isOn: selection.contains(post)) {
                selection.toggle(post)
            }
            .padding(4)
        }
        .contextMenu {
            PostImageContextMenu(model: model, post: post)
        }
    }

    private var peekFamily: [BooruPost] {
        families.cachedFamily(for: post)
    }

    private var peekFamilyHeight: CGFloat {
        peekFamily.count > 1 ? 68 : 0
    }

    @ViewBuilder
    private var peekFamilyStrip: some View {
        if peekFamily.count > 1 {
            PostFamilyStrip(
                posts: peekFamily,
                selectedID: post.globalID,
                onSelect: openRelated
            )
            .frame(height: peekFamilyHeight)
        }
    }

    private func openRelated(_ related: BooruPost) {
        if related.globalID == post.globalID { return }
        let family = peekFamily
        onDismiss()
        gallery.open(
            model: model,
            posts: family,
            selectedPostID: related.globalID,
            followsBrowseList: false
        )
    }

    private var tagsHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Tags")
                .font(.headline)
            Spacer()
            Text("\(serverDisplayName)  #\(post.id)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary.opacity(0.85))
                .lineLimit(1)
            Button(action: dismiss) {
                Image(AppIcon.close)
                    .appGlyph(size: 20)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    private func toggleTag(_ tag: String) {
        Task {
            await onToggleTag(tag)
        }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.9)) {
            appeared = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            onDismiss()
        }
    }

    private func peekHaptic() {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
    }
}
