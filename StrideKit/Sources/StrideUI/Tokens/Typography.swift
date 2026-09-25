import SwiftUI

// Type tokens. Metrics use SF Pro Expanded with tabular digits; text styles map to Dynamic Type.
public extension Font {
    /// The one live number on the run screen. Fixed size: it is already the largest that fits.
    static var metricHero: Font { .system(size: 88, weight: .heavy).width(.expanded) }
    /// Summary headlines and the Watch's main metric.
    static var metricLarge: Font { .system(size: 44, weight: .heavy).width(.expanded) }
    /// Metric tiles in grids.
    static var metricMedium: Font { .system(.title, weight: .bold).width(.expanded) }
    /// Metrics in rows and Watch secondary pages.
    static var metricSmall: Font { .system(.title3, weight: .bold).width(.expanded) }
    /// Uppercase label above a metric.
    static var metricLabel: Font { .system(.caption2, weight: .semibold) }
}

public extension View {
    /// Uppercase, tracked, muted label placed above a metric: TIME, AVG PACE.
    func metricLabelStyle() -> some View {
        font(.metricLabel)
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(.inkMuted)
    }
}
