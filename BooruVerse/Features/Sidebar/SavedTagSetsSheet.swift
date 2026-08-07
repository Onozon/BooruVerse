import SwiftUI

struct SavedTagSetsSheet: View {
    @Bindable var model: BrowseViewModel
    @Environment(\.dismiss) private var dismiss

    /// Observe the store directly — nested access via BrowseViewModel.computed was
    /// unreliable for sheet presentation on macOS.
    @State private var store = SavedTagSetStore.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.sets.isEmpty {
                    ContentUnavailableView(
                        "No Saved Sets",
                        systemImage: "tray",
                        description: Text("Save the current tags with the button next to Search.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.sets) { set in
                                Button {
                                    Task {
                                        await model.applySavedTagSet(set)
                                        dismiss()
                                    }
                                } label: {
                                    SavedTagSetRow(set: set, model: model)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 12)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("Delete", role: .destructive) {
                                        store.delete(set)
                                    }
                                }

                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Saved Tag Sets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                store.reloadFromDisk()
                resolveAllTagColors()
            }
            .onChange(of: store.revision) { _, _ in
                resolveAllTagColors()
            }
        }
#if os(macOS)
        .frame(minWidth: 320, idealWidth: 480, minHeight: 280, idealHeight: 420)
#endif
    }

    private func resolveAllTagColors() {
        let tags = store.sets.flatMap(\.tags)
        model.resolveTagNames(tags)
    }
}

private struct SavedTagSetRow: View {
    let set: SavedTagSet
    @Bindable var model: BrowseViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(set.name)
                .font(.headline)
                .foregroundStyle(.primary)

            FlowLayout(spacing: 7) {
                ForEach(set.tags, id: \.self) { tag in
                    TagChip(
                        text: tag,
                        style: .page,
                        tint: model.tagType(for: tag).color
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}
