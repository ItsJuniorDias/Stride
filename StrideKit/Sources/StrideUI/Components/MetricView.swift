import SwiftUI

/// A label over a number with an optional unit. Numbers use tabular digits and count smoothly.
public struct MetricView: View {
    public enum Size: Sendable {
        case hero, large, medium, small

        var font: Font {
            switch self {
            case .hero: .metricHero
            case .large: .metricLarge
            case .medium: .metricMedium
            case .small: .metricSmall
            }
        }
    }

    let label: String
    let value: String
    let unit: String?
    let size: Size
    let alignment: HorizontalAlignment

    public init(_ label: String, value: String, unit: String? = nil, size: Size = .medium, alignment: HorizontalAlignment = .leading) {
        self.label = label
        self.value = value
        self.unit = unit
        self.size = size
        self.alignment = alignment
    }

    public var body: some View {
        VStack(alignment: alignment, spacing: Space.x2) {
            Text(label).metricLabelStyle()
            HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                Text(value)
                    .font(size.font)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.inkMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .accessibilityElement(children: .combine)
    }
}

/// A ``MetricView`` on a raised card, for grids on the summary and detail screens.
public struct MetricTile: View {
    let label: String
    let value: String
    let unit: String?

    public init(_ label: String, value: String, unit: String? = nil) {
        self.label = label
        self.value = value
        self.unit = unit
    }

    public var body: some View {
        MetricView(label, value: value, unit: unit, size: .medium)
            .padding(Space.x4)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
    }
}
