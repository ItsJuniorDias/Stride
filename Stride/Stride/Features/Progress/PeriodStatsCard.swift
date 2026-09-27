import Foundation
import SwiftUI
import Charts
import StrideKit
import StrideUI

/// Distance, runs, time, pace and climbing for a week, month, year or all time, with a bar per
/// day, month or year, and how it compares with the period before.
struct PeriodStatsCard: View {
    let samples: [RunSample]
    let firstRun: Date?
    let now: Date
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.statsPeriod) private var period: StatsPeriod = .month
    @AppStorage(StrideSettings.yearlyGoal) private var yearlyGoal = 1_000.0
    /// Periods back from the current one: 0 is this week, month or year.
    @State private var offset = 0
    @State private var selectedDate: Date?
    @State private var upsell: ProFeature?

    /// Year and all time come with Stride Pro; week and month are free.
    private var isLocked: Bool { (period == .year || period == .all) && !ProStore.shared.isPro }

    private var interval: DateInterval {
        RunStats.interval(of: period, containing: RunStats.shifted(now, period: period, by: -offset), firstRun: firstRun)
    }

    var body: some View {
        let interval = interval
        let totals = RunStats.totals(of: samples, in: interval)
        VStack(alignment: .leading, spacing: Space.x3) {
            PillPicker("Period", selection: $period, options: StatsPeriod.allCases) { $0.title }

            if isLocked {
                lockedCard(totals: totals, interval: interval)
            } else {
                stats(interval: interval, totals: totals)
            }
        }
        .onChange(of: period) {
            offset = 0
            selectedDate = nil
        }
        .onChange(of: offset) { selectedDate = nil }
        .sensoryFeedback(.selection, trigger: offset)
        .proPaywall($upsell)
    }

    /// Year or all time without Pro: what it would show and the way in. The yearly goal is the
    /// runner's own, so its progress stays visible.
    private func lockedCard(totals: RunTotals, interval: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            ArtThumbnail(name: "recordsTrophy", width: nil, height: 130)
            HStack(spacing: Space.x2) {
                Text(period == .all ? "All time" : "Your year").font(.title3.bold()).foregroundStyle(.ink)
                TagBadge("Pro")
            }
            .accessibilityElement(children: .combine)
            Text(period == .all
                 ? "Every year since your first run, side by side, with your totals and pace."
                 : "A bar for every month, how it compares with last year, and your totals and pace.")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button("See Stride Pro") { upsell = .stats }
                .buttonStyle(.strideSecondary)
            if period == .year, offset == 0 {
                yearlyGoalWell(distance: totals.distance, interval: interval)
                    .padding(.top, Space.x1)
            }
        }
        .raisedCard()
    }

    private func stats(interval: DateInterval, totals: RunTotals) -> some View {
        let buckets = RunStats.buckets(of: samples, period: period, in: interval)
        return VStack(alignment: .leading, spacing: Space.x4) {
            header(interval)
            distance(totals: totals, interval: interval)
            PeriodChart(buckets: buckets, period: period, unit: unit, now: now, selectedDate: $selectedDate)
            totalsRow(totals)
            if period == .year, offset == 0 {
                yearlyGoalWell(distance: totals.distance, interval: interval)
            }
        }
        .raisedCard()
    }

    // MARK: Header

    private func header(_ interval: DateInterval) -> some View {
        HStack(spacing: 0) {
            if period != .all {
                arrow("chevron.left", label: "Previous \(period.title.lowercased())", enabled: canGoBack(interval)) { offset += 1 }
            }
            VStack(spacing: 0) {
                Text(title(interval)).font(.headline).foregroundStyle(.ink)
                Text(caption(interval)).font(.footnote.weight(.medium)).foregroundStyle(.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            if period != .all {
                arrow("chevron.right", label: "Next \(period.title.lowercased())", enabled: offset > 0) { offset -= 1 }
            }
        }
        .frame(minHeight: Dimension.hitMin)
        // The arrows' tap targets reach into the card's padding, as drawn.
        .padding(.horizontal, -10)
        .padding(.top, -10)
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.ink : Color.line)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private func canGoBack(_ interval: DateInterval) -> Bool {
        guard let firstRun else { return false }
        return interval.start > firstRun
    }

    private func title(_ interval: DateInterval) -> String {
        switch (period, offset) {
        case (.week, 0): "This week"
        case (.week, 1): "Last week"
        case (.month, 0): "This month"
        case (.month, 1): "Last month"
        case (.year, 0): "This year"
        case (.year, 1): "Last year"
        case (.all, _): "All time"
        case (.week, _): dayRange(interval)
        case (.month, _): interval.start.formatted(.dateTime.month(.wide).year())
        case (.year, _): interval.start.formatted(.dateTime.year())
        }
    }

    private func caption(_ interval: DateInterval) -> String {
        switch period {
        case .week: offset < 2 ? dayRange(interval) : weekCaption(interval)
        case .month: offset < 2 ? interval.start.formatted(.dateTime.month(.wide).year()) : "\(interval.start.formatted(.dateTime.month(.abbreviated))) 1 – \(lastDay(interval).formatted(.dateTime.day()))"
        case .year: interval.start.formatted(.dateTime.year())
        case .all: firstRun.map { "Since \($0.formatted(.dateTime.month(.wide).year()))" } ?? "No runs yet"
        }
    }

    private func weekCaption(_ interval: DateInterval) -> String {
        "Week \(Calendar.current.component(.weekOfYear, from: interval.start))"
    }

    private func lastDay(_ interval: DateInterval) -> Date {
        interval.end.addingTimeInterval(-1)
    }

    private func dayRange(_ interval: DateInterval) -> String {
        let calendar = Calendar.current
        let sameYear = calendar.isDate(interval.start, equalTo: now, toGranularity: .year)
        let style: Date.FormatStyle = sameYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year()
        return "\(interval.start.formatted(style)) – \(lastDay(interval).formatted(style))"
    }

    // MARK: Distance

    private func distance(totals: RunTotals, interval: DateInterval) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text("Distance").metricLabelStyle()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(RunFormat.distance(totals.distance, unit: unit, fractionDigits: 1))
                    .font(.metricLarge)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit.distanceSymbol)
                    .font(.headline)
                    .foregroundStyle(.inkMuted)
            }
            if let comparison = comparison(totals: totals, interval: interval) {
                HStack(spacing: 6) {
                    Image(systemName: comparison.symbol)
                        .font(.system(size: 14, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(comparison.text)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(comparison.isMore ? Color.success : Color.inkMuted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// "12% more than this point last month". Nil when there's nothing to compare with.
    private func comparison(totals: RunTotals, interval: DateInterval) -> (text: String, symbol: String, isMore: Bool)? {
        guard let previous = RunStats.previousInterval(of: period, before: interval, now: now) else { return nil }
        let before = RunStats.totals(of: samples, in: previous).distance
        guard before > 0 else { return nil }
        let unitName = period.title.lowercased()
        let reference = interval.containsHalfOpen(now) ? "this point last \(unitName)" : "the \(unitName) before"
        let change = (totals.distance - before) / before
        let percent = Int((abs(change) * 100).rounded())
        if percent == 0 {
            return ("Same distance as \(reference)", "equal", false)
        } else if change > 0 {
            return ("\(percent)% more than \(reference)", "arrow.up.right", true)
        } else {
            return ("\(percent)% less than \(reference)", "arrow.down.right", false)
        }
    }

    // MARK: Totals

    private func totalsRow(_ totals: RunTotals) -> some View {
        HStack(alignment: .top, spacing: Space.x2) {
            total("Runs", value: Text("\(totals.runs)"), spoken: "\(totals.runs)")
            Spacer(minLength: 0)
            total("Time", value: hoursAndMinutes(totals.duration), spoken: spokenDuration(totals.duration))
            Spacer(minLength: 0)
            let pace = RunFormat.pace(totals.averagePace(in: unit))
            total("Pace \(unit.paceSymbol)", value: Text(pace), spoken: "\(pace) \(unit.paceSymbol)")
            Spacer(minLength: 0)
            let climb = Int(unit.elevation(fromMeters: totals.elevationGain).rounded()).formatted()
            total("Climb", value: Text("\(Text(climb))\(small(" \(unit.elevationSymbol)"))"),
                  spoken: "\(climb) \(unit.elevationSymbol)")
        }
        .lineLimit(1)
        .padding(.top, Space.x4)
        .overlay(alignment: .top) { Hairline() }
    }

    private func total(_ label: String, value: Text, spoken: String) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(label).metricLabelStyle()
            value
                .font(.metricSmall)
                .monospacedDigit()
                .foregroundStyle(.ink)
                .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spoken)
    }

    /// "9h 58m", "45m", or "290h" once minutes stop mattering.
    private func hoursAndMinutes(_ seconds: TimeInterval) -> Text {
        let minutes = Int((max(seconds, 0) / 60).rounded())
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return Text("\(Text("\(rest)"))\(small("m"))") }
        if hours >= 100 { return Text("\(Text("\(hours)"))\(small("h"))") }
        return Text("\(Text("\(hours)"))\(small("h")) \(Text("\(rest)"))\(small("m"))")
    }

    private func spokenDuration(_ seconds: TimeInterval) -> String {
        Duration.seconds(max(seconds, 0)).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    private func small(_ text: String) -> Text {
        Text(text).font(.footnote.weight(.semibold)).foregroundStyle(Color.inkMuted)
    }

    // MARK: Yearly goal

    private func yearlyGoalWell(distance: Double, interval: DateInterval) -> some View {
        let done = distance / unit.metersPerUnit
        let elapsed = min(max(now.timeIntervalSince(interval.start) / interval.duration, 0), 1)
        return VStack(alignment: .leading, spacing: Space.x2) {
            HStack(alignment: .firstTextBaseline) {
                Text("Yearly goal").font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                Spacer()
                Text("\(Int(done).formatted()) of \(Int(yearlyGoal).formatted()) \(unit.distanceSymbol)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.inkMuted)
            }
            TrackBar(progress: yearlyGoal > 0 ? done / yearlyGoal : 0, track: .surfaceRaised)
            // A projection needs a few weeks of the year behind it to mean anything.
            if elapsed > 0.05, done > 0, done < yearlyGoal {
                let projected = done / elapsed
                Text(projected >= yearlyGoal
                     ? "On pace for \(Int(projected).formatted()) \(unit.distanceSymbol) this year"
                     : "\(Int((yearlyGoal - done).rounded(.up)).formatted()) \(unit.distanceSymbol) to go · on pace for \(Int(projected).formatted())")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(projected >= yearlyGoal ? Color.success : Color.inkMuted)
            } else if done >= yearlyGoal {
                Text("Goal reached").font(.footnote.weight(.semibold)).foregroundStyle(.success)
            }
        }
        .raisedCard(padding: Space.x3, fill: .surfaceSunken)
        .accessibilityElement(children: .combine)
    }
}

/// A bar per day, month or year in the data color, on a dashed grid of three round steps. Days
/// without a run show a short stub; days still to come show nothing. Touch a bar to read it.
private struct PeriodChart: View {
    let buckets: [StatsBucket]
    let period: StatsPeriod
    let unit: UnitSystem
    let now: Date
    @Binding var selectedDate: Date?

    /// Top rounded, bottom nearly square, as drawn.
    private static let barShape = UnevenRoundedRectangle(topLeadingRadius: 4, bottomLeadingRadius: 2,
                                                         bottomTrailingRadius: 2, topTrailingRadius: 4)

    var body: some View {
        let values = buckets.map { $0.totals.distance / unit.metersPerUnit }
        let step = Self.step(for: values.max() ?? 0)
        let ticks = (0...3).map { Double($0) * step }
        let selected = selectedDate.flatMap { date in buckets.first { $0.start <= date && date < $0.end } }
        let component = period.bucketComponent
        Chart {
            ForEach(buckets) { bucket in
                let value = bucket.totals.distance / unit.metersPerUnit
                if value > 0 {
                    if bucket.start == selected?.start {
                        bar(bucket, value: value, component: component, dimmed: false)
                            .annotation(position: .top, spacing: Space.x1,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                selectionLabel(bucket)
                            }
                    } else {
                        bar(bucket, value: value, component: component, dimmed: selected != nil)
                    }
                } else {
                    // A 2pt stub on days without a run; nothing on days still to come.
                    BarMark(x: .value("Date", bucket.start, unit: component),
                            yStart: .value("Distance", 0.0), yEnd: .value("Distance", 0.0),
                            width: .ratio(barRatio))
                        .offset(x: 0, yStart: 0, yEnd: bucket.start > now ? 0 : -2)
                        .foregroundStyle(bucket.start > now ? Color.clear : Color.line)
                        .accessibilityLabel(label(for: bucket))
                        .accessibilityValue(bucket.start > now ? "" : "No runs")
                        .accessibilityHidden(bucket.start > now)
                }
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartYScale(domain: 0...(step * 3))
        .chartXAxis { xAxis }
        .chartYAxis {
            AxisMarks(position: .leading, values: ticks) { value in
                if value.index == 0 {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                        .foregroundStyle(Color.line)
                } else {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .foregroundStyle(Color.lineStrong.opacity(0.45))
                }
                AxisValueLabel {
                    if let distance = value.as(Double.self) {
                        Text(Int(distance.rounded()).formatted())
                    }
                }
                .font(.caption2)
                .foregroundStyle(Color.inkMuted)
            }
        }
        .frame(height: 132)
        .accessibilityLabel(caption)
    }

    private func bar(_ bucket: StatsBucket, value: Double, component: Calendar.Component, dimmed: Bool) -> some ChartContent {
        BarMark(x: .value("Date", bucket.start, unit: component),
                y: .value("Distance", value),
                width: .ratio(barRatio))
            .foregroundStyle(dimmed ? Color.lane.opacity(0.35) : Color.lane)
            .clipShape(Self.barShape)
            .accessibilityLabel(label(for: bucket))
            .accessibilityValue(spokenValue(bucket))
    }

    /// Bars take about 70% of their slot, as drawn at every period.
    private var barRatio: Double { period == .all ? 0.6 : 0.7 }

    private var xAxis: some AxisContent {
        let (component, count, format): (Calendar.Component, Int, Date.FormatStyle) = switch period {
        case .week: (.day, 1, .dateTime.weekday(.narrow))
        case .month: (.day, 7, .dateTime.day())
        case .year: (.month, 1, .dateTime.month(.narrow))
        case .all: (.year, 1, .dateTime.year())
        }
        return AxisMarks(values: .stride(by: component, count: count)) { _ in
            AxisValueLabel(format: format, centered: true)
                .font(.caption2)
                .foregroundStyle(Color.inkMuted)
        }
    }

    private func selectionLabel(_ bucket: StatsBucket) -> some View {
        let runs = bucket.totals.runs
        let distance = "\(RunFormat.distance(bucket.totals.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
        return Text("\(shortLabel(for: bucket)) · \(distance) · \(runs) \(runs == 1 ? "run" : "runs")")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(.ink)
            .padding(.horizontal, Space.x2)
            .padding(.vertical, Space.x1)
            .background(Color.surfaceSunken, in: Capsule())
            .fixedSize()
    }

    private var caption: String {
        switch period {
        case .week, .month: "Distance per day"
        case .year: "Distance per month"
        case .all: "Distance per year"
        }
    }

    private func label(for bucket: StatsBucket) -> String {
        switch period {
        case .week, .month: bucket.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .year: bucket.start.formatted(.dateTime.month(.wide).year())
        case .all: bucket.start.formatted(.dateTime.year())
        }
    }

    private func shortLabel(for bucket: StatsBucket) -> String {
        switch period {
        case .week, .month: bucket.start.formatted(.dateTime.weekday(.abbreviated).day())
        case .year: bucket.start.formatted(.dateTime.month(.wide))
        case .all: bucket.start.formatted(.dateTime.year())
        }
    }

    private func spokenValue(_ bucket: StatsBucket) -> String {
        let runs = bucket.totals.runs
        return "\(RunFormat.distance(bucket.totals.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol), \(runs) \(runs == 1 ? "run" : "runs")"
    }

    /// A round step so three of them clear the longest bar: 5, 10, 15 or 40, 80, 120. At least 1.
    static func step(for maximum: Double) -> Double {
        let raw = max(maximum / 3, 1)
        let magnitude = pow(10, floor(log10(raw)))
        let fraction = raw / magnitude
        let nice: Double = [1, 2, 3, 4, 5, 6, 8, 10].first { fraction <= $0 + 1e-9 } ?? 10
        return nice * magnitude
    }
}
