import SwiftUI

struct FavoriteFolderPickerSheet: View {
    @State private var store = FavoritePostStore.shared
    @State private var selectedFolderID: String = FavoritePostStore.defaultFolderID
    @State private var newFolderName = ""
    @Environment(\.dismiss) private var dismiss

    private var isCreatingNew: Bool {
        selectedFolderID == Self.newFolderSentinel
    }

    private static let newFolderSentinel = "__new__"

    private var folderPreviewEntries: [FavoriteEntry] {
        guard !isCreatingNew else { return [] }
        return store.previewEntries(in: selectedFolderID, limit: 4)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Folder") {
                    ForEach(store.folders) { folder in
                        folderRow(id: folder.id, title: folder.name)
                    }
                    folderRow(id: Self.newFolderSentinel, title: "New folder")

                    if isCreatingNew {
                        TextField("Folder name", text: $newFolderName)
                    }
                }

                Section("In selected folder") {
                    if isCreatingNew {
                        Text("New folder is empty")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else if folderPreviewEntries.isEmpty {
                        Text(emptyFolderMessage)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        HStack(spacing: 8) {
                            ForEach(folderPreviewEntries) { entry in
                                RemoteThumbnail(url: entry.previewURL, contentMode: .fill)
                                    .frame(width: 64, height: 64)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)

                        Text(folderCountLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(store.pendingAllowsMove ? "Move to Folder" : "Add to Favorites")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        store.cancelPendingAdd()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(store.pendingAllowsMove ? "Move" : "Add") {
                        confirm()
                    }
                    .disabled(isCreatingNew && newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                selectedFolderID = store.folders.contains(where: { $0.id == store.lastFolderID })
                    ? store.lastFolderID
                    : FavoritePostStore.defaultFolderID
            }
        }
#if os(macOS)
        .frame(minWidth: 360, minHeight: 320)
#endif
    }

    private var emptyFolderMessage: String {
        let count = store.postCount(in: selectedFolderID)
        if count == 0 {
            return "Folder is empty"
        }
        return "\(count) \(count == 1 ? "post" : "posts") — previews appear after posts are favorited from the app"
    }

    private var folderCountLabel: String {
        let count = store.postCount(in: selectedFolderID)
        return count == 1 ? "1 post in folder" : "\(count) posts in folder"
    }

    private func folderRow(id: String, title: String) -> some View {
        Button {
            selectedFolderID = id
        } label: {
            HStack {
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                if selectedFolderID == id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.tint)
                        .fontWeight(.semibold)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func confirm() {
        if isCreatingNew {
            store.confirmPendingAddNewFolder(name: newFolderName)
        } else {
            store.confirmPendingAdd(folderID: selectedFolderID)
        }
        dismiss()
    }
}
