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
                Text("Training load").font(.headline).foregroundStyle(.ink)
                if isLocked { TagBadge("Pro") }
                Spacer()
                if let load {
                    StatusChip(chipTitle(load.state), indicator: chipColor(load.state))
                }
            }
            .accessibilityElement(children: .combine)

            if isLocked {
                ProgressProTeaser(symbol: "chart.line.uptrend.xyaxis",
                                  text: "How this week compares with your usual, and whether your pace is getting faster.") {
                    upsell = .trends
                }
            } else if load == nil, trend == nil {
                Text("Run a few more times over the next weeks to see your training load and pace trend.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .raisedCard()
            } else {
                VStack(alignment: .leading, spacing: Space.x4) {
                    if let load {
                        loadSection(load)
                    } else {
                        Text("Your training load shows up after three weeks of runs.")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }
                    Divider()
                    if let trend {
                        trendSection(trend)
                    } else {
                        Text("Your pace trend shows up after runs in \(PaceTrend.minimumWeeks) different weeks.")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }
                }
                .raisedCard()
            }
        }
        .proPaywall($upsell)
    }

    // MARK: Load

    private func loadSection(_ load: TrainingLoad) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(alignment: .top, spacing: Space.x4) {
                MetricView("Last 7 days", value: RunFormat.distance(load.acute, unit: unit, fractionDigits: 1),
                           unit: unit.distanceSymbol, size: .medium)
                MetricView("Your usual week", value: RunFormat.distance(load.chronic, unit: unit, fractionDigits: 1),
                           unit: unit.distanceSymbol, size: .medium)
            }
            LoadGauge(load: load)
            Text(message(load.state))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        return VStack(alignment: .leading, spacing: Space.x2) {
            Text("Pace trend").metricLabelStyle()
            Text(sentence)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(seconds > 0 && change < 0 ? Color.success : Color.ink)
                .fixedSize(horizontal: false, vertical: true)
            PaceSparkline(trend: trend, unit: unit)
                .frame(height: 64)
                .padding(.top, Space.x1)
            HStack {
                Text(weeksAgoLabel(trend.weeks.first?.weeksAgo ?? 0))
                Spacer()
                Text(weeksAgoLabel(trend.weeks.last?.weeksAgo ?? 0))
            }
            .font(.caption2)
            .foregroundStyle(.inkMuted)
            .accessibilityHidden(true)
            Text("Average pace per week, from runs of \(shortest) \(unit.distanceSymbol) or more.")
                .font(.caption)
                .foregroundStyle(.inkMuted)
        }
    }

    private func weeksAgoLabel(_ weeksAgo: Int) -> String {
        switch weeksAgo {
        case 0: "Last 7 days"
        case 1: "1 week ago"
        default: "\(weeksAgo) weeks ago"
        }
    }
}

/// The last 7 days as a bar against the usual week (the tick), over the band where training
/// builds without ramping too fast.
private struct LoadGauge: View {
    let load: TrainingLoad
    private var barHeight: CGFloat { 10 }

    var body: some View {
        // Room past the ramp limit, so a usual week sits left of center and a jump shows as one.
        let scale = max(load.acute, load.chronic * 1.6, 1)
        GeometryReader { geo in
            let width = geo.size.width
            let low = width * fraction(load.chronic * TrainingLoad.easingLimit, of: scale)
            let high = width * fraction(load.chronic * TrainingLoad.rampLimit, of: scale)
            let usual = width * fraction(load.chronic, of: scale)
            let done = width * fraction(load.acute, of: scale)
            ZStack(alignment: .leading) {
                ZStack(alignment: .leading) {
                    Rectangle().fill(Color.surfaceSunken)
                    Rectangle()
                        .fill(Color.success.opacity(0.2))
                        .frame(width: max(high - low, 0))
                        .offset(x: low)
                    Capsule()
                        .fill(load.state == .rampTooFast ? Color.warning : Color.lane)
                        .frame(width: load.acute > 0 ? max(done, barHeight) : 0)
                }
                .frame(height: barHeight)
                .clipShape(Capsule())
                Capsule()
                    .fill(Color.ink)
                    .frame(width: 3, height: barHeight + 8)
                    .offset(x: min(max(usual - 1.5, 0), width - 3))
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: barHeight + 8)
        .animation(.snappy, value: load.acute)
        .accessibilityHidden(true)
    }

    private func fraction(_ meters: Double, of scale: Double) -> CGFloat {
        CGFloat(min(max(meters / scale, 0), 1))
    }
}

/// Average pace per week with the trend line through it. Faster is up, like the pace chart.
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
            ForEach(trend.weeks) { week in
                LineMark(x: .value("Week", week.start), y: .value("Pace", perUnit(week.pace)), series: .value("Line", "weeks"))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Color.lane)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel(week.start.formatted(.dateTime.month(.abbreviated).day()))
                    .accessibilityValue("\(RunFormat.pace(perUnit(week.pace))) \(unit.paceSymbol)")
                PointMark(x: .value("Week", week.start), y: .value("Pace", perUnit(week.pace)))
                    .foregroundStyle(Color.lane)
                    .symbolSize(24)
                    .accessibilityHidden(true)
            }
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
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: .automatic(includesZero: false, reversed: true, dataType: Double.self) {
            $0 = [low - padding, high + padding]
        })
        .chartPlotStyle { $0.clipped() }
    }

    private func perUnit(_ secondsPerKilometer: Double) -> Double {
        TrainingPaces.perUnit(secondsPerKilometer, unit: unit)
    }
}
