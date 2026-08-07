import SwiftUI

struct PostTagsListView: View {
    let groups: [BooruTagGroup]
    let onAddTag: (String) -> Void

    var body: some View {
        ScrollView {
            PostTagsListContent(groups: groups, onAddTag: onAddTag)
        }
    }
}

struct PostTagsListContent: View {
    let groups: [BooruTagGroup]
    let onAddTag: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(groups) { group in
                PostTagGroupSection(group: group, onAddTag: onAddTag)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct PostTagGroupSection: View {
    let group: BooruTagGroup
    let onAddTag: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(group.type.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(group.type.color)
                .padding(.top, 2)

            FlowLayout(spacing: 7) {
                ForEach(group.tags) { tag in
                    Button {
                        onAddTag(tag.name)
                    } label: {
                        TagChip(
                            text: tag.name,
                            style: .page,
                            tint: tag.type.color,
                            count: nil
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
