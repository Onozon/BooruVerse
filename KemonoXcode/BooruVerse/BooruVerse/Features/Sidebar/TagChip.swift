import SwiftUI

enum TagChipStyle {
    case active
    case suggestion
    case page
}

extension String {
    /// Inserts break opportunities after underscores so long tag names wrap readably.
    var tagWrappedForDisplay: String {
        replacingOccurrences(of: "_", with: "_\u{200B}")
    }
}

struct TagChip: View {
    let text: String
    var style: TagChipStyle = .active
    var tint: Color?
    var count: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Text(text.tagWrappedForDisplay)
                .font(chipFont)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let count {
                Text(count, format: .number)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(secondaryTextColor)
            }
        }
        .foregroundStyle(primaryTextColor)
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(backgroundColor, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(borderColor)
        }
    }

    private var cornerRadius: CGFloat {
        style == .page ? 14 : 12
    }

    private var chipFont: Font {
        switch style {
        case .page: .subheadline
        case .active, .suggestion: .caption
        }
    }

    private var horizontalPadding: CGFloat {
        style == .page ? 11 : 8
    }

    private var verticalPadding: CGFloat {
        style == .page ? 6 : 4
    }

    private var backgroundColor: Color {
        switch style {
        case .active:
            Color.accentColor.opacity(0.15)
        case .suggestion:
            Color.gray.opacity(0.12)
        case .page:
            (tint ?? .secondary).opacity(0.14)
        }
    }

    private var borderColor: Color {
        switch style {
        case .active, .suggestion:
            Color.secondary.opacity(0.25)
        case .page:
            (tint ?? .secondary).opacity(0.38)
        }
    }

    private var primaryTextColor: Color {
        switch style {
        case .active, .suggestion:
            Color.primary
        case .page:
            tint ?? .primary
        }
    }

    private var secondaryTextColor: Color {
        switch style {
        case .page:
            (tint ?? .secondary).opacity(0.75)
        default:
            .secondary
        }
    }
}

#Preview {
    VStack {
        TagChip(text: "very_long_character_tag_name", style: .page, tint: .green)
        TagChip(text: "solo", style: .page, tint: .blue, count: 12)
    }
    .frame(width: 180)
    .padding()
}
