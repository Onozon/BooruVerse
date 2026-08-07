import SwiftUI

struct TagSuggestionsListView: View {
    let suggestions: [BooruTag]
    var isLoading = false
    let onSelect: (BooruTag) -> Void

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if suggestions.isEmpty {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text("Try a different spelling.")
                )
            } else {
                List(suggestions) { tag in
                    Button {
                        onSelect(tag)
                    } label: {
                        TagSuggestionRow(tag: tag)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
    }
}

struct TagSuggestionRow: View {
    let tag: BooruTag

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(tag.name.tagWrappedForDisplay)
                .foregroundStyle(tag.type.color)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Text(tag.postCount, format: .number)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}
