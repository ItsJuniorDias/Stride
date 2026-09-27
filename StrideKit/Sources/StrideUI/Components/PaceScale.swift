import SwiftUI
import StrideKit

/// Pace colors for routes and splits, on the zone palette: blue where faster than the run's
/// average (zone 2), green around it (zone 3), yellow a little slower (zone 4), orange slower (zone 5).
/// The same thresholds as the pace-colored route on the map.
public enum PaceScale {
    /// `ratio` is speed ÷ average speed (average pace ÷ pace): above 1 is faster than average.
    public static func color(forSpeedRatio ratio: Double) -> Color {
        switch ratio {
        case 1.05...: Palette.zone2
        case 0.98..<1.05: Palette.zone3
        case 0.92..<0.98: Palette.zone4
        default: Palette.zone5
        }
    }

    /// A split's or a stretch's color from its pace and the run's average pace, both in seconds per
    /// unit. Green when either is missing.
    public static func color(pace: Double?, average: Double?) -> Color {
        guard let pace, let average, pace > 0, average > 0 else { return Palette.zone3 }
        return color(forSpeedRatio: average / pace)
    }

    /// Faster to slower, left to right, for legends.
    public static var gradient: LinearGradient {
        LinearGradient(colors: [Palette.zone2, Palette.zone3, Palette.zone4, Palette.zone5],
                       startPoint: .leading, endPoint: .trailing)
    }
}

/// "Faster ▬ Slower": the key to a pace-colored route, on a glass capsule over the map.
public struct PaceScaleLegend: View {
    let faster: String
    let slower: String
    let isGlass: Bool

    public init(faster: String = "Faster", slower: String = "Slower", glass: Bool = true) {
        self.faster = faster
        self.slower = slower
        self.isGlass = glass
    }

    public var body: some View {
        HStack(spacing: Space.x2) {
            Text(faster)
            Capsule()
                .fill(PaceScale.gradient)
                .frame(width: 64, height: 6)
            Text(slower)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.ink)
        .padding(.horizontal, Space.x3)
        .frame(height: 32)
        .background {
            if isGlass {
                Color.clear.floatingGlass(in: Capsule(), interactive: false)
            } else {
                Capsule().fill(Color.surfaceRaised)
            }
        }
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Route color: pace, blue faster, orange slower")
    }
}
