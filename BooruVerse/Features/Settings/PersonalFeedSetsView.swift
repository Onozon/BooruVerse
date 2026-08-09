import SwiftUI

struct PersonalFeedSetsView: View {
    private var savedStore = SavedTagSetStore.shared
    private var personalStore = PersonalFeedStore.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        let _ = savedStore.revision
        let _ = personalStore.revision

        Group {
            if savedStore.sets.isEmpty {
                ContentUnavailableView(
                    "No Saved Tag Sets",
                    systemImage: "bookmark",
                    description: Text("Save a tag set from Browse, then enable it here for your Personal feed.")
                )
            } else {
                Form {
                    Section {
                        ForEach(savedStore.sets) { set in
                            Toggle(isOn: binding(for: set)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(set.name)
                                    Text(set.tags.joined(separator: " "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                        }
                    } footer: {
                        Text("Selected sets are searched together. Duplicate posts across sets appear only once, ordered by newest first.")
                    }
                }
#if os(macOS)
                .formStyle(.grouped)
#endif
            }
        }
        .frame(maxWidth: contentWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .navigationTitle("Personal Feed")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }

    private var contentWidth: CGFloat? {
#if os(macOS)
        horizontalSizeClass == .compact ? nil : 720
#else
        nil
#endif
    }

    private func binding(for set: SavedTagSet) -> Binding<Bool> {
        Binding(
            get: { personalStore.isInPersonal(set) },
            set: { personalStore.setPersonal(set, enabled: $0) }
        )
    }
}

#Preview {
    NavigationStack {
        PersonalFeedSetsView()
    }
}
