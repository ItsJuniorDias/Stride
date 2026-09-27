import SwiftUI
import StrideKit

/// Time in each heart-rate zone, highest zone on top, bars scaled to the longest zone.
/// `.detailed` is the run detail's rows (numbered swatch, name, bar, time, share of the run);
/// `.compact` is the Watch's rows (colored number, bar, time), with the `current` zone's time in bold.
/// Has no background: the detail screen puts it on a raised card.
public struct ZoneTimeList: View {
    public enum Style: Sendable {
        case detailed, compact
    }

    let seconds: [HeartRateZone: TimeInterval]
    let style: Style
    let current: HeartRateZone?
    let track: Color?

    /// - Parameter track: behind the bars; defaults to `surfaceSunken` for `.detailed` (on a raised
    ///   card) and `surfaceRaised` for `.compact` (on the Watch's black).
    public init(seconds: [HeartRateZone: TimeInterval], style: Style = .detailed, current: HeartRateZone? = nil,
                track: Color? = nil) {
        self.seconds = seconds
        self.style = style
        self.current = current
        self.track = track
    }

    public var body: some View {
        let total = seconds.values.reduce(0, +)
        let longest = max(seconds.values.max() ?? 0, 1)
        VStack(spacing: style == .detailed ? 6 : 5) {
            ForEach(HeartRateZone.allCases.reversed(), id: \.self) { zone in
                let time = seconds[zone] ?? 0
                let fraction = time > 0 ? max(time / longest, 0.04) : 0
                let percent = total > 0 ? Int((time / total * 100).rounded()) : 0
                Group {
                    switch style {
                    case .detailed: detailedRow(zone, time: time, fraction: fraction, percent: percent, hasHours: longest >= 3_600)
                    case .compact: compactRow(zone, time: time, fraction: fraction, hasHours: longest >= 3_600)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Zone \(zone.rawValue), \(zone.name)")
                .accessibilityValue("\(RunFormat.duration(time)), \(percent) percent")
            }
        }
    }

    /// An hour or more in a zone ("1:02:07") widens the time column for every row, so bars stay aligned.
    private func detailedRow(_ zone: HeartRateZone, time: TimeInterval, fraction: Double, percent: Int, hasHours: Bool) -> some View {
        HStack(spacing: 10) {
            ZoneSwatch(zone)
            Text(zone.name)
                .lineLimit(1)
                .frame(width: 82, alignment: .leading)
            TrackBar(progress: fraction, tint: zone.color, height: 10, track: track ?? Color.surfaceSunken)
            Text(RunFormat.duration(time))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: hasHours ? 58 : 46, alignment: .trailing)
            Text(verbatim: "\(percent)%")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 34, alignment: .trailing)
        }
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(.ink)
        .frame(minHeight: 22)
    }

    private func compactRow(_ zone: HeartRateZone, time: TimeInterval, fraction: Double, hasHours: Bool) -> some View {
        let isCurrent = zone == current
        return HStack(spacing: 6) {
            Text(verbatim: "\(zone.rawValue)")
                .font(.caption.weight(.bold))
                .foregroundStyle(zone.color)
                .frame(width: 14, alignment: .leading)
            TrackBar(progress: fraction, tint: zone.color, height: 8, track: track ?? Color.surfaceRaised)
            Text(RunFormat.duration(time))
                .font(.caption.weight(isCurrent ? .bold : .medium))
                .foregroundStyle(isCurrent ? Color.ink : Color.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: hasHours ? 52 : 40, alignment: .trailing)
        }
        .monospacedDigit()
        .frame(minHeight: 14)
    }
}
