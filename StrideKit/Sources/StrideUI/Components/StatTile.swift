import SwiftUI

/// A small symbol beside a ``StatTile`` label: the trophy on a record metric or a record tile.
public struct StatSymbol: Sendable {
    let systemImage: String
    let color: Color
    let isLeading: Bool
    let accessibilityLabel: String?

    public init(systemImage: String, color: Color = .track, isLeading: Bool = false, accessibilityLabel: String? = nil) {
        self.systemImage = systemImage
        self.color = color
        self.isLeading = isLeading
        self.accessibilityLabel = accessibilityLabel
    }

    /// Before the label, e.g. the trophy on a personal-record tile ("🏆 5K").
    public static func leading(_ systemImage: String, color: Color = .track, accessibilityLabel: String? = nil) -> StatSymbol {
        StatSymbol(systemImage: systemImage, color: color, isLeading: true, accessibilityLabel: accessibilityLabel)
    }

    /// After the label.
    public static func trailing(_ systemImage: String, color: Color = .track, accessibilityLabel: String? = nil) -> StatSymbol {
        StatSymbol(systemImage: systemImage, color: color, isLeading: false, accessibilityLabel: accessibilityLabel)
    }

    /// The trophy after a metric that set a personal record, read as "Personal record".
    public static let record = StatSymbol(systemImage: "trophy", color: .track, isLeading: false, accessibilityLabel: "Personal record")
}

/// An uppercase label over a number in SF Pro Expanded with tabular digits, an optional unit, and an
/// optional footer under it (a footnote, a ``ZoneChip``, a trend line). The workhorse of the summary,
/// detail, Progress and Watch screens. Sizes follow ``MetricView/Size``: `.small` 20pt, `.medium`
/// 28pt, `.large` 44pt, `.hero` 88pt. It has no background: put it on `.raisedCard()`, in a
/// ``DividedGrid``, or on a sunken well with `.raisedCard(padding: Space.x3, fill: .surfaceSunken)`.
public struct StatTile<Footer: View>: View {
    let label: String
    let value: String
    let unit: String?
    let size: MetricView.Size
    let alignment: HorizontalAlignment
    let symbol: StatSymbol?
    let tint: Color
    let footer: Footer

    public init(_ label: String, value: String, unit: String? = nil, size: MetricView.Size = .small,
                alignment: HorizontalAlignment = .leading, symbol: StatSymbol? = nil, tint: Color = .ink,
                @ViewBuilder footer: () -> Footer) {
        self.label = label
        self.value = value
        self.unit = unit
        self.size = size
        self.alignment = alignment
        self.symbol = symbol
        self.tint = tint
        self.footer = footer()
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: size.statSpacing) {
            labelRow
            HStack(alignment: .firstTextBaseline, spacing: size == .hero ? 6 : Space.x1) {
                Text(value)
                    .font(size.font)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let unit {
                    Text(unit)
                        .font(size.unitFont)
                        .foregroundStyle(.inkMuted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            footer
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .accessibilityElement(children: .combine)
    }

    private var labelRow: some View {
        HStack(spacing: Space.x1) {
            if let symbol, symbol.isLeading {
                symbolImage(symbol)
            }
            Text(label)
                .metricLabelStyle()
                .lineLimit(1)
            if let symbol, !symbol.isLeading {
                symbolImage(symbol)
            }
        }
    }

    private func symbolImage(_ symbol: StatSymbol) -> some View {
        Image(systemName: symbol.systemImage)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(symbol.color)
            .accessibilityLabel(symbol.accessibilityLabel ?? "")
            .accessibilityHidden(symbol.accessibilityLabel == nil)
    }
}

public extension StatTile where Footer == EmptyView {
    init(_ label: String, value: String, unit: String? = nil, size: MetricView.Size = .small,
         alignment: HorizontalAlignment = .leading, symbol: StatSymbol? = nil, tint: Color = .ink) {
        self.init(label, value: value, unit: unit, size: size, alignment: alignment, symbol: symbol, tint: tint) {
            EmptyView()
        }
    }
}

public extension StatTile where Footer == Text {
    /// With a 13pt muted line under the number: "4'48" /km", "Sep 22", "Most runs".
    init(_ label: String, value: String, unit: String? = nil, size: MetricView.Size = .small,
         alignment: HorizontalAlignment = .leading, symbol: StatSymbol? = nil, tint: Color = .ink, footnote: String) {
        self.init(label, value: value, unit: unit, size: size, alignment: alignment, symbol: symbol, tint: tint) {
            Text(footnote)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
        }
    }
}

private extension MetricView.Size {
    /// Label to number.
    var statSpacing: CGFloat {
        switch self {
        case .hero: Space.x1
        case .large: Space.x2
        case .medium: 6
        case .small: Space.x1
        }
    }

    /// Units stay in SF Pro Text and step down with the number.
    var unitFont: Font {
        switch self {
        case .hero: .title3.weight(.semibold)
        case .large, .medium: .subheadline.weight(.semibold)
        case .small: .footnote.weight(.medium)
        }
    }
}
