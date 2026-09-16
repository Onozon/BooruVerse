import SwiftUI

struct FavoriteFolderSidebar: View {
    var onFolderSelected: (() -> Void)? = nil

    @State private var store = FavoritePostStore.shared
    @State private var renameTarget: FavoriteFolder?
    @State private var renameText = ""
    @State private var deleteTarget: FavoriteFolder?
    @State private var creating = false
    @State private var newName = ""

    var body: some View {
        List {
            ForEach(store.folders) { folder in
                Button {
                    selectFolder(folder.id)
                } label: {
                    HStack {
                        Text(folder.name)
                            .foregroundStyle(store.activeFolderID == folder.id ? Color.accentColor : Color.primary)
                            .fontWeight(store.activeFolderID == folder.id ? .semibold : .regular)
                        Spacer()
                        Text("\(store.postCount(in: folder.id))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    if folder.id != FavoritePostStore.defaultFolderID {
                        Button("Rename…") {
                            renameTarget = folder
                            renameText = folder.name
                        }
                        Button("Delete…", role: .destructive) {
                            deleteTarget = folder
                        }
                    }
                }
            }

            Button {
                creating = true
                newName = ""
            } label: {
                Label("New Folder", appIcon: AppIcon.add)
            }
        }
        .alert("New Folder", isPresented: $creating) {
            TextField("Name", text: $newName)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let id = store.createFolder(name: newName)
                if !id.isEmpty {
                    selectFolder(id)
                }
            }
        }
        .alert("Rename Folder", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                if let id = renameTarget?.id {
                    store.renameFolder(id: id, name: renameText)
                }
                renameTarget = nil
            }
        }
        .confirmationDialog(
            "Delete Folder?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Folder & Posts", role: .destructive) {
                if let id = deleteTarget?.id {
                    store.deleteFolder(id: id, deletePosts: true)
                }
                deleteTarget = nil
            }
            Button("Delete Folder, Keep Posts") {
                if let id = deleteTarget?.id {
                    store.deleteFolder(id: id, deletePosts: false)
                }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: {
            Text("Posts can move to Favorites or be removed from favorites entirely.")
        }
    }

    private func selectFolder(_ id: String) {
        store.activeFolderID = id
        onFolderSelected?()
    }
}
