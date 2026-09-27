import SwiftUI
import StrideKit

extension Color {
    /// Text on a solid zone color: the dark ink reads on all five zones in both themes.
    static let onZone = Color(hex: 0x12161C)
}

/// The heart-rate zone as a small capsule. `.tinted` is the live run's "Z4 · Threshold" (a 14%
/// wash with a dot, text in the zone color); `.solid` is the Watch's "Z3" (dark text on the zone
/// color). The number is always there, so the color is never the only cue.
public struct ZoneChip: View {
    public enum Style: Sendable {
        case tinted, solid
    }

    let zone: HeartRateZone
    let style: Style
    let showsName: Bool

    public init(_ zone: HeartRateZone, style: Style = .tinted, showsName: Bool = true) {
        self.zone = zone
        self.style = style
        self.showsName = showsName
    }

    public var body: some View {
        Group {
            switch style {
            case .tinted:
                HStack(spacing: 6) {
                    Circle().fill(zone.color).frame(width: 6, height: 6)
                    Text(title)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(zone.color)
                .padding(.horizontal, Space.x2)
                .frame(minHeight: 22)
                .background(zone.color.opacity(0.14), in: Capsule())
            case .solid:
                Text(title)
                    .font(.caption2.weight(.bold))
                    .tracking(0.4)
                    .foregroundStyle(Color.onZone)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(zone.color, in: Capsule())
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Zone \(zone.rawValue), \(zone.name)")
    }

    private var title: String {
        showsName ? "Z\(zone.rawValue) · \(zone.name)" : "Z\(zone.rawValue)"
    }
}

/// The zone number on a rounded square of its color, leading a zone row.
public struct ZoneSwatch: View {
    let zone: HeartRateZone
    let size: CGFloat

    public init(_ zone: HeartRateZone, size: CGFloat = 22) {
        self.zone = zone
        self.size = size
    }

    public var body: some View {
        Text(verbatim: "\(zone.rawValue)")
            .font(.system(size: size * 0.55, weight: .heavy).width(.expanded))
            .foregroundStyle(Color.onZone)
            .frame(width: size, height: size)
            .background(zone.color, in: RoundedRectangle(cornerRadius: size * 0.27))
            .accessibilityLabel("Zone \(zone.rawValue)")
    }
}

/// The five zone colors side by side: numbered 20pt blocks in onboarding (`showsNumbers`), a 6pt
/// strip under Max HR on Profile, and on the Watch's zone page with the current zone lit, the others
/// faded, and a `marker` tick at the heart rate's place along the whole scale (0…1).
public struct ZoneScale: View {
    let height: CGFloat
    let showsNumbers: Bool
    let highlighted: HeartRateZone?
    let marker: Double?

    public init(height: CGFloat = 6, showsNumbers: Bool = false, highlighted: HeartRateZone? = nil, marker: Double? = nil) {
        self.height = height
        self.showsNumbers = showsNumbers
        self.highlighted = highlighted
        self.marker = marker
    }

    public var body: some View {
        HStack(spacing: showsNumbers ? Space.x1 : 3) {
            ForEach(HeartRateZone.allCases, id: \.self) { zone in
                RoundedRectangle(cornerRadius: showsNumbers ? 6 : height / 2)
                    .fill(zone.color)
                    .opacity(highlighted == nil || highlighted == zone ? 1 : 0.3)
                    .frame(height: height)
                    .overlay {
                        if showsNumbers {
                            Text(verbatim: "\(zone.rawValue)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(Color.onZone)
                        }
                    }
            }
        }
        .overlay {
            if let marker {
                GeometryReader { geo in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.ink)
                        .frame(width: 3, height: height * 2)
                        .background {
                            RoundedRectangle(cornerRadius: 2.5).fill(Color.surface).padding(-1.5)
                        }
                        .position(x: geo.size.width * min(max(marker, 0), 1), y: geo.size.height / 2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(highlighted.map { "Zone \($0.rawValue), \($0.name)" } ?? "Heart rate zones 1 to 5")
    }
}
