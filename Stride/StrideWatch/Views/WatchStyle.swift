import Foundation
import SwiftUI
import StrideKit
import StrideUI

// Pieces shared by the Watch screens, from the approved Watch artboards (drawn at 208 × 248 pt).
// Colors are the design system's tokens, which resolve to their Watch values on watchOS.

// MARK: Type

extension Font {
    /// A live number in SF Pro Expanded with tabular digits. Fixed, like the design system's metric
    /// fonts, so the workout pages keep their layout at every text size.
    static func watchMetric(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight).width(.expanded).monospacedDigit()
    }
}

extension View {
    /// Text at one of the artboards' sizes (11 pt labels, 12 pt captions, 13 pt status, 15 pt rows,
    /// 17 pt titles), scaled with the wearer's text size.
    func watchFont(_ size: CGFloat, _ weight: Font.Weight = .regular, digits: Bool = false) -> some View {
        modifier(WatchFont(size: size, weight: weight, digits: digits))
    }
}

private struct WatchFont: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight
    private let digits: Bool

    init(size: CGFloat, weight: Font.Weight, digits: Bool) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: Self.textStyle(for: size))
        self.weight = weight
        self.digits = digits
    }

    func body(content: Content) -> some View {
        let font = Font.system(size: size, weight: weight)
        return content.font(digits ? font.monospacedDigit() : font)
    }

    /// The text style each size grows with.
    private static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case ..<12: .caption2
        case ..<13: .caption
        case ..<15: .footnote
        case ..<17: .body
        default: .headline
        }
    }
}

// MARK: Labels

/// The small uppercase label over a group: GOALS, THIS WEEK, TIME IN ZONES.
struct WatchOverline: View {
    let title: String
    let inset: CGFloat

    init(_ title: String, inset: CGFloat = 0) {
        self.title = title
        self.inset = inset
    }

    var body: some View {
        Text(title)
            .watchFont(11, .semibold)
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(.inkMuted)
            .lineLimit(1)
            .padding(.leading, inset)
            .accessibilityAddTraits(.isHeader)
    }
}

/// The unit after a live number: KM, /KM, M LEFT.
struct WatchUnitLabel: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .watchFont(11, .semibold)
            .tracking(0.9)
            .textCase(.uppercase)
            .foregroundStyle(.inkMuted)
            .lineLimit(1)
            .fixedSize()
    }
}

/// What the run is for, in muted text; "Paused" in warning while paused, after a pause glyph on the
/// metrics page.
struct WatchRunStatus: View {
    let title: String
    let isPaused: Bool
    var showsIcon = true

    var body: some View {
        HStack(spacing: 5) {
            if isPaused && showsIcon {
                Image(systemName: "pause.fill")
                    .font(.system(size: 10, weight: .bold))
                    .accessibilityHidden(true)
            }
            Text(isPaused ? "Paused" : title)
                .watchFont(13, .semibold)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(isPaused ? Color.warning : Color.inkMuted)
        .frame(minHeight: 22)
    }
}

// MARK: Metrics

/// A live number with its unit after it: 4.21 KM, 5'38" /KM.
struct WatchMetricRow: View {
    let value: String
    let unit: String
    let accessibilityText: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value)
                .font(.watchMetric(28))
                .foregroundStyle(.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            WatchUnitLabel(unit)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }
}

/// Heart rate, a heart in the zone's color and the zone chip: 148 ♥ Z3.
struct WatchHeartRateRow: View {
    let heartRate: Double?
    let zone: HeartRateZone?

    var body: some View {
        HStack(spacing: 6) {
            Text(heartRate.map { "\(Int($0))" } ?? RunFormat.empty)
                .font(.watchMetric(28))
                .foregroundStyle(.ink)
                .lineLimit(1)
            Image(systemName: "heart.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(zone?.color ?? Color.inkMuted)
            if let zone {
                ZoneChip(zone, style: .solid, showsName: false)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let heartRate else { return "Heart rate unavailable" }
        guard let zone else { return "Heart rate \(Int(heartRate)), below zone 1" }
        return "Heart rate \(Int(heartRate)), zone \(zone.rawValue), \(zone.name.lowercased())"
    }
}

// MARK: Buttons

/// A row or tile on the Watch's black: a `surfaceRaised` rounded card that shrinks a little when
/// pressed and dims when disabled.
struct WatchCardButtonStyle: ButtonStyle {
    var fill: Color = .surfaceRaised
    var cornerRadius: CGFloat = Radius.md

    func makeBody(configuration: Configuration) -> some View {
        WatchCardButtonBody(configuration: configuration, fill: fill, cornerRadius: cornerRadius)
    }
}

private struct WatchCardButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let fill: Color
    let cornerRadius: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        configuration.label
            .background(fill, in: shape)
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A 44 pt capsule: Done on the summary (`track`), Cancel on the countdown (`surfaceRaised`).
struct WatchCapsuleButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color
    var fontSize: CGFloat = 17
    var fillsWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .watchFont(fontSize, .semibold)
            .foregroundStyle(foreground)
            .lineLimit(1)
            .padding(.horizontal, 22)
            .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: Dimension.hitMin)
            .frame(minWidth: 120)
            .background(fill, in: Capsule())
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

extension View {
    /// The flat `surfaceRaised` card the Watch groups things in.
    func watchCard(fill: Color = .surfaceRaised) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }
}

// MARK: Words

extension WorkoutManager.Goal {
    /// What the run is for: "5 km goal", "Half marathon goal", "30 min goal", the workout's name,
    /// or "Free run".
    var title: String {
        switch type {
        case .free:
            return "Free run"
        case .intervals:
            return name ?? "Intervals"
        case .distance:
            if let distance, abs(distance - 21_097.5) < 1 { return "Half marathon goal" }
            if let distance, abs(distance - 42_195) < 1 { return "Marathon goal" }
            if let name, !name.isEmpty { return "\(name) goal" }
            if let distance {
                return "\((distance / 1_000).formatted(.number.precision(.fractionLength(0...2)))) km goal"
            }
            return "Distance goal"
        case .time:
            if let name, !name.isEmpty { return "\(name) goal" }
            if let duration { return "\(Int(duration / 60)) min goal" }
            return "Time goal"
        }
    }
}

/// What VoiceOver reads for the Watch's numbers, instead of `5'38"` or `24:18`.
enum WatchSpeech {
    /// "24 minutes, 18 seconds".
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "unknown" }
        return Duration.seconds(Int(seconds)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide))
    }

    /// "Pace 5 minutes, 38 seconds per kilometer".
    static func pace(_ secondsPerUnit: Double?, unit: UnitSystem) -> String {
        guard let secondsPerUnit, secondsPerUnit.isFinite, secondsPerUnit > 0, secondsPerUnit < 3_600 else {
            return "Pace unavailable"
        }
        return "Pace \(duration(secondsPerUnit.rounded())) per \(unitName(unit, plural: false))"
    }

    /// "4.21 kilometers".
    static func distance(_ meters: Double, unit: UnitSystem) -> String {
        "\(RunFormat.distance(meters, unit: unit)) \(unitName(unit, plural: true))"
    }

    static func unitName(_ unit: UnitSystem, plural: Bool) -> String {
        switch unit {
        case .metric: plural ? "kilometers" : "kilometer"
        case .imperial: plural ? "miles" : "mile"
        }
    }
}
