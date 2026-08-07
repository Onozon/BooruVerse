import SwiftUI

struct PostImageContextMenu: View {
    @Bindable var model: BrowseViewModel
    let post: BooruPost
    let onExport: () -> Void
    let onSaveError: (String) -> Void

    var body: some View {
        Button {
            model.toggleFavorite(post)
        } label: {
            if model.isFavorite(post) {
                Label("Remove from Favorites", systemImage: "heart.fill")
            } else {
                Label("Add to Favorites", systemImage: "heart")
            }
        }

        Button {
            Task {
                do {
                    try await model.savePostToPhotos(post)
                } catch {
                    onSaveError(error.localizedDescription)
                }
            }
        } label: {
            Label("Save to Photos", systemImage: "photo")
        }

        Button(action: onExport) {
            Label("Save As…", systemImage: "square.and.arrow.down")
        }
    }
}

struct PostImageActionBar: View {
    @Bindable var model: BrowseViewModel
    let post: BooruPost
    let onExport: () -> Void
    let onSaveError: (String) -> Void
    var usesLightContent = false

    private var contentColor: Color {
        usesLightContent ? .white : .primary
    }

    private var favoriteColor: Color {
        model.isFavorite(post) ? .pink : contentColor
    }

    private var dividerColor: Color {
        usesLightContent ? .white.opacity(0.28) : Color.primary.opacity(0.2)
    }

    var body: some View {
        HStack(spacing: 0) {
            actionButton(
                title: model.isFavorite(post) ? "Favorited" : "Favorite",
                systemImage: model.isFavorite(post) ? "heart.fill" : "heart",
                tint: favoriteColor
            ) {
                model.toggleFavorite(post)
            }

            Divider()
                .frame(height: 28)
                .overlay(dividerColor)

            actionButton(title: "Photos", systemImage: "photo") {
                Task {
                    do {
                        try await model.savePostToPhotos(post)
                    } catch {
                        onSaveError(error.localizedDescription)
                    }
                }
            }

            Divider()
                .frame(height: 28)
                .overlay(dividerColor)

            actionButton(title: "Save As", systemImage: "square.and.arrow.down") {
                onExport()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private func actionButton(
        title: String,
        systemImage: String,
        tint: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.body.weight(.medium))
                Text(title)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint ?? contentColor)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
