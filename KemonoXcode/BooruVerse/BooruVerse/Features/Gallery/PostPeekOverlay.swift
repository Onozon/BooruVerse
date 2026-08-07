import SwiftUI
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

struct PostPeekOverlay: View {
    @Bindable var model: BrowseViewModel
    let post: BooruPost
    let onAddTag: (String) async -> Void
    let onDismiss: () -> Void

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var appeared = false
    @State private var exportDocument: SavedImageDocument?
    @State private var showFileExporter = false
    @State private var exportFilename = "image.jpg"
    @State private var exportContentType: UTType = .jpeg
    @State private var actionError: String?

    private var tagGroups: [BooruTagGroup] {
        model.postTagGroups(for: post)
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
        }
        .fileExporter(
            isPresented: $showFileExporter,
            document: exportDocument,
            contentType: exportContentType,
            defaultFilename: exportFilename
        ) { result in
            if case .failure(let error) = result {
                actionError = error.localizedDescription
            }
        }
        .alert("Error", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(actionError ?? "")
        }
    }

    @ViewBuilder
    private func card(in size: CGSize) -> some View {
        let cardWidth = min(size.width - 32, horizontalSizeClass == .compact ? 360 : 640)
        let cardHeight = min(size.height * 0.78, horizontalSizeClass == .compact ? 560 : 480)
        let headerHeight: CGFloat = 36
        let actionsHeight: CGFloat = 56
        let imageHeight = (cardHeight - headerHeight - actionsHeight) * 0.52
        let tagsHeight = cardHeight - imageHeight - headerHeight - actionsHeight

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

            tagsHeader
                .frame(height: headerHeight)

            PostTagsListView(groups: tagGroups, onAddTag: addTag)
                .frame(height: tagsHeight)

            Divider()

            PostImageActionBar(
                model: model,
                post: post,
                onExport: { Task { await prepareExport() } },
                onSaveError: { actionError = $0 }
            )
            .frame(height: actionsHeight)
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
                peekImage
                    .frame(width: cardWidth * 0.48, height: cardHeight - actionsHeight)

                Divider()

                VStack(alignment: .leading, spacing: 0) {
                    tagsHeader
                        .frame(height: headerHeight)

                    PostTagsListView(groups: tagGroups, onAddTag: addTag)
                }
                .frame(width: cardWidth * 0.52 - 1)
            }

            Divider()

            PostImageActionBar(
                model: model,
                post: post,
                onExport: { Task { await prepareExport() } },
                onSaveError: { actionError = $0 }
            )
            .frame(height: actionsHeight)
        }
        .frame(width: cardWidth, height: cardHeight)
    }

    private var peekImage: some View {
        RemoteThumbnail(url: post.previewURL, contentMode: .fit)
            .aspectRatio(post.aspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(8)
            .background(Color.primary.opacity(0.04))
    }

    private var tagsHeader: some View {
        HStack {
            Text("Tags")
                .font(.headline)
            Spacer()
            Text("#\(post.id)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Button(action: dismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
    }

    private func addTag(_ tag: String) {
        dismiss()
        Task {
            await onAddTag(tag)
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

    private func prepareExport() async {
        do {
            exportDocument = try await model.exportDocument(for: post)
            exportFilename = PostImageSaver.defaultFilename(for: post)
            exportContentType = PostImageSaver.contentType(for: post)
            showFileExporter = true
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func peekHaptic() {
#if canImport(UIKit)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
#endif
    }
}
