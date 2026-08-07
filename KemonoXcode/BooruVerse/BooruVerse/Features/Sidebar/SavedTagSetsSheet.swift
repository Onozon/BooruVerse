import SwiftUI

struct SavedTagSetsSheet: View {
    @Bindable var model: BrowseViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if model.savedTagSets.isEmpty {
                    ContentUnavailableView(
                        "No Saved Sets",
                        systemImage: "tray",
                        description: Text("Save the current tags with the button next to Search.")
                    )
                } else {
                    List {
                        ForEach(model.savedTagSets) { set in
                            Button {
                                Task {
                                    await model.applySavedTagSet(set)
                                    dismiss()
                                }
                            } label: {
                                SavedTagSetRow(set: set, model: model)
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete { indexSet in
                            let sets = model.savedTagSets
                            for index in indexSet {
                                model.deleteSavedTagSet(sets[index])
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Saved Tag Sets")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                resolveAllTagColors()
            }
            .onChange(of: model.savedTagSets) { _, _ in
                resolveAllTagColors()
            }
        }
    }

    private func resolveAllTagColors() {
        let tags = model.savedTagSets.flatMap(\.tags)
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
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}
