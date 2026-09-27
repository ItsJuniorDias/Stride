import SwiftUI
import Charts
import StrideKit
import StrideUI

/// Progress: the last 7 days against the runner's usual week, and whether their pace is getting
/// faster. Stride Pro; without it, what the card shows in words and the way in.
struct TrainingLoadCard: View {
    let samples: [RunSample]
    let now: Date
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var upsell: ProFeature?

    private var isLocked: Bool { !ProStore.shared.isPro }

    var body: some View {
        let load = isLocked ? nil : TrainingLoad.compute(samples: samples, now: now)
        let trend = isLocked ? nil : PaceTrend.compute(samples: samples, now: now)
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x2) {
                Text("Training load")
                    .font(.headline)
                    .foregroundStyle(.ink)
                    .accessibilityAddTraits(.isHeader)
                if isLocked { TagBadge("Pro") }
                Spacer(minLength: 0)
                if let load {
                    StatusChip(chipTitle(load.state), indicator: chipColor(load.state), background: chipBackground(load.state))
                }
            }
            .frame(minHeight: 28)

            if isLocked {
                ProgressProTeaser(symbol: "chart.line.uptrend.xyaxis",
                                  text: "How this week compares with your usual, and whether your pace is getting faster.") {
                    upsell = .trends
                }
            } else if load == nil, trend == nil {
                Text("Run a few more times over the next weeks to see your training load and pace trend.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if let load {
                    loadSection(load)
                } else {
                    Text("Your training load shows up after three weeks of runs.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
                Group {
                    if let trend {
                        trendSection(trend)
                    } else {
                        Text("Your pace trend shows up after runs in \(PaceTrend.minimumWeeks) different weeks.")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, Space.x4)
                .overlay(alignment: .top) { Hairline() }
                .padding(.top, Space.x1)
            }
        }
        .raisedCard()
        .proPaywall($upsell)
    }

    // MARK: Load

    private func loadSection(_ load: TrainingLoad) -> some View {
        // Room past the ramp limit, so a usual week sits left of center and a jump shows as one.
        let scale = max(load.acute, load.chronic * 1.6, 1)
        let low = load.chronic * TrainingLoad.easingLimit
        let high = load.chronic * TrainingLoad.rampLimit
        let range = "\(whole(low))–\(whole(high)) \(unit.distanceSymbol)"
        return VStack(alignment: .leading, spacing: Space.x3) {
            VStack(alignment: .leading, spacing: Space.x3) {
                HStack(alignment: .top, spacing: Space.x3) {
                    StatTile("Last 7 days", value: RunFormat.distance(load.acute, unit: unit, fractionDigits: 1),
                             unit: unit.distanceSymbol, size: .medium)
                    StatTile("Your usual week", value: RunFormat.distance(load.chronic, unit: unit, fractionDigits: 1),
                             unit: unit.distanceSymbol, size: .medium)
                }
                TrackBar(progress: load.acute / scale,
                         tint: load.state == .rampTooFast ? .warning : .lane,
                         height: 12,
                         marker: load.chronic / scale,
                         band: (low / scale)...(high / scale),
                         bandColor: .success,
                         bandPlacement: .below)
                    .padding(.top, Space.x1)
                HStack(spacing: Space.x4) {
                    HStack(spacing: 6) {
                        Capsule().fill(Color.success).frame(width: 14, height: 4)
                        Text("Safe build, \(range)")
                    }
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.ink).frame(width: 3, height: 12)
                        Text("Your usual week")
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Last 7 days, \(RunFormat.distance(load.acute, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol), against a usual week of \(RunFormat.distance(load.chronic, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol). Safe build, \(whole(low)) to \(whole(high)) \(unit.distanceSymbol).")
            Text(message(load.state))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Meters as whole kilometers or miles.
    private func whole(_ meters: Double) -> String {
        Int((meters / unit.metersPerUnit).rounded()).formatted()
    }

    private func chipTitle(_ state: TrainingLoad.State) -> String {
        switch state {
        case .easing: "Easing off"
        case .steady: "Steady"
        case .building: "Building"
        case .rampTooFast: "Ramping fast"
        }
    }

    private func chipColor(_ state: TrainingLoad.State) -> Color {
        switch state {
        case .easing: .lineStrong
        case .steady: .success
        case .building: .lane
        case .rampTooFast: .warning
        }
    }

    private func chipBackground(_ state: TrainingLoad.State) -> Color {
        switch state {
        case .easing: .surfaceSunken
        case .steady: Color.success.opacity(0.16)
        case .building: .laneSoft
        case .rampTooFast: Color.warning.opacity(0.16)
        }
    }

    private func message(_ state: TrainingLoad.State) -> String {
        switch state {
        case .easing: "You're easing off: a lighter week than usual."
        case .steady: "You're steady: close to your usual week."
        case .building: "You're building: a little more than your usual week."
        case .rampTooFast: "You're ramping up fast: consider an easy week."
        }
    }

    // MARK: Pace trend

    private func trendSection(_ trend: PaceTrend) -> some View {
        let change = TrainingPaces.perUnit(trend.change, unit: unit)
        let seconds = Int(abs(change).rounded())
        let direction = change < 0 ? "faster" : "slower"
        let sentence = seconds == 0
            ? "Your pace has held steady over the last \(trend.span) weeks."
            : "Your pace is \(seconds) s\(unit.paceSymbol) \(direction) than \(trend.span) weeks ago."
        let shortest = RunFormat.distance(PaceTrend.shortestRun, unit: unit, fractionDigits: unit == .metric ? 0 : 1)
        return VStack(alignment: .leading, spacing: Space.x1) {
            Text("Pace trend").metricLabelStyle()
            Text(sentence)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(seconds > 0 && change < 0 ? Color.success : Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            PaceSparkline(trend: trend, unit: unit)
                .frame(height: 56)
                .padding(.top, Space.x2)
            HStack {
                if let first = trend.weeks.first { Text(endLabel(first)) }
                Spacer(minLength: Space.x2)
                if let last = trend.weeks.last { Text(endLabel(last)) }
            }
            .font(.caption2)
            .monospacedDigit()
            .foregroundStyle(.inkMuted)
            .accessibilityHidden(true)
            Text("Weekly average of runs over \(shortest) \(unit.distanceSymbol). Up is faster.")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "8 weeks ago · 5'58"", "Last 7 days · 5'52"".
    private func endLabel(_ week: PaceTrend.Week) -> String {
        let when = switch week.weeksAgo {
        case 0: "Last 7 days"
        case 1: "1 week ago"
        default: "\(week.weeksAgo) weeks ago"
        }
        return "\(when) · \(RunFormat.pace(TrainingPaces.perUnit(week.pace, unit: unit)))"
    }
}

/// Average pace per week, straight from week to week, with the trend line through it and the latest
/// week marked. Faster is up, like the pace chart.
private struct PaceSparkline: View {
    let trend: PaceTrend
    let unit: UnitSystem

    var body: some View {
        let paces = trend.weeks.map { perUnit($0.pace) }
        let first = trend.weeks.first
        let last = trend.weeks.last
        let ends = [first, last].compactMap { $0 }
        let fitted = ends.map { perUnit(trend.fitted(weeksAgo: $0.weeksAgo)) }
        let low = (paces + fitted).min() ?? 0
        let high = (paces + fitted).max() ?? 1
        let padding = max((high - low) * 0.15, 3)
        Chart {
            if let first, let last, first.weeksAgo != last.weeksAgo {
                LineMark(x: .value("Week", first.start), y: .value("Pace", perUnit(trend.fitted(weeksAgo: first.weeksAgo))),
                         series: .value("Line", "trend"))
                    .foregroundStyle(Color.inkMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityHidden(true)
                LineMark(x: .value("Week", last.start), y: .value("Pace", perUnit(trend.fitted(weeksAgo: last.weeksAgo))),
                         series: .value("Line", "trend"))
                    .foregroundStyle(Color.inkMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityHidden(true)
            }
            ForEach(trend.weeks) { week in
                LineMark(x: .value("Week", week.start), y: .value("Pace", perUnit(week.pace)), series: .value("Line", "weeks"))
                    .interpolationMethod(.linear)
                    .foregroundStyle(Color.lane)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel(week.start.formatted(.dateTime.month(.abbreviated).day()))
                    .accessibilityValue("\(RunFormat.pace(perUnit(week.pace))) \(unit.paceSymbol)")
                if week.id == last?.id {
                    PointMark(x: .value("Week", week.start), y: .value("Pace", perUnit(week.pace)))
                        .symbol {
                            Circle()
                                .fill(Color.lane)
                                .frame(width: 9, height: 9)
                                .overlay { Circle().stroke(Color.surfaceRaised, lineWidth: 2) }
                        }
                        .accessibilityHidden(true)
                } else {
                    PointMark(x: .value("Week", week.start), y: .value("Pace", perUnit(week.pace)))
                        .foregroundStyle(Color.lane)
                        .symbolSize(28)
                        .accessibilityHidden(true)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false, reversed: true, dataType: Double.self) {
            $0 = [low - padding, high + padding]
        })
        // Room for the first and last points, which sit on the ends.
        .chartXScale(range: .plotDimension(padding: 6))
    }

    private func perUnit(_ secondsPerKilometer: Double) -> Double {
        TrainingPaces.perUnit(secondsPerKilometer, unit: unit)
    }
}
