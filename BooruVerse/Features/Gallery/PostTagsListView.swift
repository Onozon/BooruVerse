import SwiftUI

struct PostTagsListView: View {
    let groups: [BooruTagGroup]
    var selectedTags: Set<String> = []
    let onToggleTag: (String) -> Void

    var body: some View {
        ScrollView {
            PostTagsListContent(
                groups: groups,
                selectedTags: selectedTags,
                onToggleTag: onToggleTag
            )
        }
    }
}

struct PostTagsListContent: View {
    let groups: [BooruTagGroup]
    var selectedTags: Set<String> = []
    let onToggleTag: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups) { group in
                PostTagGroupSection(
                    group: group,
                    selectedTags: selectedTags,
                    onToggleTag: onToggleTag
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct PostTagGroupSection: View {
    let group: BooruTagGroup
    var selectedTags: Set<String> = []
    let onToggleTag: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.type.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(group.type.color)
                .padding(.top, 2)

            FlowLayout(spacing: 7) {
                ForEach(group.tags) { tag in
                    Button {
                        onToggleTag(tag.name)
                    } label: {
                        TagChip(
                            text: tag.name,
                            style: .page,
                            tint: tag.type.color,
                            count: nil,
                            isSelected: selectedTags.contains(tag.name)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}
