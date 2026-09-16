import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

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
    /// When true (page/active chips), use brighter fill/border like Qt selected chips.
    var isSelected: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 5) {
            Text(text.tagWrappedForDisplay)
                .font(chipFont)
                .fontWeight(isSelected ? .semibold : .regular)
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
                .strokeBorder(borderColor, lineWidth: isSelected ? 1.5 : 1)
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

    private var displayTint: Color {
        let base = tint ?? .secondary
        return isSelected ? base.mix(with: .white, by: 0.35) : base
    }

    private var backgroundColor: Color {
        switch style {
        case .active:
            Color.accentColor.opacity(isSelected ? 0.28 : 0.15)
        case .suggestion:
            Color.gray.opacity(0.12)
        case .page:
            displayTint.opacity(isSelected ? 0.32 : 0.14)
        }
    }

    private var borderColor: Color {
        switch style {
        case .active, .suggestion:
            Color.secondary.opacity(isSelected ? 0.45 : 0.25)
        case .page:
            displayTint.opacity(isSelected ? 0.85 : 0.38)
        }
    }

    private var primaryTextColor: Color {
        switch style {
        case .active, .suggestion:
            Color.primary
        case .page:
            displayTint
        }
    }

    private var secondaryTextColor: Color {
        switch style {
        case .page:
            displayTint.opacity(isSelected ? 0.9 : 0.75)
        default:
            .secondary
        }
    }
}

private extension Color {
    /// Approximate Qt.lighter for selected page-chip tints.
    func mix(with other: Color, by amount: CGFloat) -> Color {
        let t = max(0, min(1, amount))
#if canImport(UIKit)
        let uiSelf = UIColor(self)
        let uiOther = UIColor(other)
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        uiSelf.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        uiOther.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return Color(
            red: r1 + (r2 - r1) * t,
            green: g1 + (g2 - g1) * t,
            blue: b1 + (b2 - b1) * t,
            opacity: a1 + (a2 - a1) * t
        )
#else
        // macOS: resolve through NSColor when possible.
        let nsSelf = NSColor(self)
        let nsOther = NSColor(other)
        guard let c1 = nsSelf.usingColorSpace(.sRGB),
              let c2 = nsOther.usingColorSpace(.sRGB) else {
            return self
        }
        return Color(
            red: c1.redComponent + (c2.redComponent - c1.redComponent) * t,
            green: c1.greenComponent + (c2.greenComponent - c1.greenComponent) * t,
            blue: c1.blueComponent + (c2.blueComponent - c1.blueComponent) * t,
            opacity: c1.alphaComponent + (c2.alphaComponent - c1.alphaComponent) * t
        )
#endif
    }
}

#Preview {
    VStack {
        TagChip(text: "very_long_character_tag_name", style: .page, tint: .green)
        TagChip(text: "solo", style: .page, tint: .blue, count: 12, isSelected: true)
    }
    .frame(width: 180)
    .padding()
}
