import SwiftUI

/// Rows in one raised card with `line` hairlines between them, inset from the leading edge so they
/// start where the row's text does (16pt plain rows, 80pt after a 56pt thumbnail, 64pt after a 36pt
/// icon). Pass the rows as separate views, e.g. ``CardRow``s or buttons; each row pads itself.
/// Outside a `List`, so rows that need swipe actions belong in a `List` instead.
public struct GroupedCard<Content: View>: View {
    let dividerInset: CGFloat
    let fill: Color
    let content: Content

    public init(dividerInset: CGFloat = Space.x4, fill: Color = .surfaceRaised, @ViewBuilder content: () -> Content) {
        self.dividerInset = dividerInset
        self.fill = fill
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(subviews) { subview in
                    subview
                    if subview.id != subviews.last?.id {
                        Hairline(leadingInset: dividerInset)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(fill, in: RoundedRectangle(cornerRadius: Radius.md))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

/// A 1pt `line` rule between rows, optionally inset from the leading edge.
public struct Hairline: View {
    let leadingInset: CGFloat

    public init(leadingInset: CGFloat = 0) {
        self.leadingInset = leadingInset
    }

    public var body: some View {
        Rectangle()
            .fill(Color.line)
            .frame(height: 1)
            .padding(.leading, leadingInset)
            .accessibilityHidden(true)
    }
}

/// A row for a ``GroupedCard`` or a standalone raised card: optional leading art or ``IconBadge``,
/// a 17pt title with an optional 13pt subtitle, and an optional trailing accessory (value, toggle,
/// ``DisclosureChevron``). At least 52pt tall, padded 12 × 16, the whole row tappable when wrapped in
/// a `Button` or `NavigationLink`.
public struct CardRow<Leading: View, Trailing: View>: View {
    let title: String
    let subtitle: String?
    let titleWeight: Font.Weight
    let subtitleColor: Color
    let leading: Leading
    let trailing: Trailing

    public init(_ title: String, subtitle: String? = nil, titleWeight: Font.Weight = .semibold,
                subtitleColor: Color = .inkMuted,
                @ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.titleWeight = titleWeight
        self.subtitleColor = subtitleColor
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(spacing: Space.x3) {
            leading
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(titleWeight))
                    .foregroundStyle(.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(subtitleColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.vertical, Space.x3)
        .padding(.horizontal, Space.x4)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
    }
}

public extension CardRow where Leading == EmptyView {
    init(_ title: String, subtitle: String? = nil, titleWeight: Font.Weight = .semibold,
         subtitleColor: Color = .inkMuted, @ViewBuilder trailing: () -> Trailing) {
        self.init(title, subtitle: subtitle, titleWeight: titleWeight, subtitleColor: subtitleColor) {
            EmptyView()
        } trailing: {
            trailing()
        }
    }
}

public extension CardRow where Leading == EmptyView, Trailing == EmptyView {
    init(_ title: String, subtitle: String? = nil, titleWeight: Font.Weight = .semibold, subtitleColor: Color = .inkMuted) {
        self.init(title, subtitle: subtitle, titleWeight: titleWeight, subtitleColor: subtitleColor) {
            EmptyView()
        } trailing: {
            EmptyView()
        }
    }
}

/// The muted chevron at the end of a row that opens something.
public struct DisclosureChevron: View {
    public init() {}

    public var body: some View {
        Image(systemName: "chevron.right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.inkMuted)
            .accessibilityHidden(true)
    }
}
