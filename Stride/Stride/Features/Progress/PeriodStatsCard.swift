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
        let buckets = RunStats.buckets(of: samples, period: period, in: interval)
        VStack(alignment: .leading, spacing: Space.x3) {
            Picker("Period", selection: $period) {
                ForEach(StatsPeriod.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)

            if isLocked {
                lockedCard(totals: totals, interval: interval)
            } else {
                stats(interval: interval, totals: totals, buckets: buckets)
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
            Illustration(name: "recordsTrophy", contentMode: .fill)
                .frame(height: 130)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            HStack(spacing: Space.x2) {
                Text(period == .all ? "All time" : "Your year").font(.title3.bold()).foregroundStyle(.ink)
                TagBadge("Pro")
            }
            Text(period == .all
                 ? "Every year since your first run, side by side, with your totals and pace."
                 : "A bar for every month, how it compares with last year, and your totals and pace.")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
            Button("See Stride Pro") { upsell = .stats }
                .buttonStyle(.strideSecondary)
            if period == .year, offset == 0 {
                yearlyGoalRow(distance: totals.distance, interval: interval)
                    .padding(.top, Space.x2)
            }
        }
        .raisedCard()
    }

    private func stats(interval: DateInterval, totals: RunTotals, buckets: [StatsBucket]) -> some View {
            VStack(alignment: .leading, spacing: Space.x4) {
                header(interval)

                VStack(alignment: .leading, spacing: Space.x1) {
                    MetricView("Distance", value: RunFormat.distance(totals.distance, unit: unit, fractionDigits: 1),
                               unit: unit.distanceSymbol, size: .large)
                    if let comparison = comparison(totals: totals, interval: interval) {
                        comparison
                    }
                }

                chart(buckets)

                Grid(horizontalSpacing: Space.x4, verticalSpacing: Space.x4) {
                    GridRow {
                        MetricView("Runs", value: "\(totals.runs)", size: .small)
                        MetricView("Time", value: totalTime(totals.duration), size: .small)
                    }
                    GridRow {
                        MetricView("Avg pace", value: RunFormat.pace(totals.averagePace(in: unit)), unit: unit.paceSymbol, size: .small)
                        MetricView("Climbing", value: Int(unit.elevation(fromMeters: totals.elevationGain).rounded()).formatted(),
                                   unit: unit.elevationSymbol, size: .small)
                    }
                }

                if period == .year, offset == 0 {
                    yearlyGoalRow(distance: totals.distance, interval: interval)
                }
            }
            .raisedCard()
    }

    // MARK: Header

    private func header(_ interval: DateInterval) -> some View {
        HStack(spacing: Space.x2) {
            if period != .all {
                arrow("chevron.left", label: "Previous \(period.title.lowercased())", enabled: canGoBack(interval)) { offset += 1 }
            }
            VStack(spacing: 2) {
                Text(title(interval)).font(.headline).foregroundStyle(.ink)
                Text(caption(interval)).font(.caption).foregroundStyle(.inkMuted)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            if period != .all {
                arrow("chevron.right", label: "Next \(period.title.lowercased())", enabled: offset > 0) { offset -= 1 }
            }
        }
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
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

    // MARK: Comparison

    /// "12% more than this point last month". Nothing when there's nothing to compare with.
    private func comparison(totals: RunTotals, interval: DateInterval) -> Text? {
        guard let previous = RunStats.previousInterval(of: period, before: interval, now: now) else { return nil }
        let before = RunStats.totals(of: samples, in: previous).distance
        guard before > 0 else { return nil }
        let unitName = period.title.lowercased()
        let reference = interval.containsHalfOpen(now) ? "this point last \(unitName)" : "the \(unitName) before"
        let change = (totals.distance - before) / before
        let percent = Int((abs(change) * 100).rounded())
        let text: String
        let symbol: String
        if percent == 0 {
            text = "Same distance as \(reference)"
            symbol = "equal"
        } else if change > 0 {
            text = "\(percent)% more than \(reference)"
            symbol = "arrow.up.right"
        } else {
            text = "\(percent)% less than \(reference)"
            symbol = "arrow.down.right"
        }
        return Text("\(Image(systemName: symbol)) \(text)")
            .font(.subheadline.weight(.medium))
            .foregroundStyle(change > 0 && percent > 0 ? Color.success : Color.inkMuted)
    }

    // MARK: Chart

    private func chart(_ buckets: [StatsBucket]) -> some View {
        let selected = selectedDate.flatMap { date in buckets.first { $0.start <= date && date < $0.end } }
        let component = period.bucketComponent
        return VStack(alignment: .leading, spacing: Space.x2) {
            Text(chartCaption(selected))
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.inkMuted)
                .contentTransition(.numericText())
            Chart(buckets) { bucket in
                BarMark(x: .value("Date", bucket.start, unit: component),
                        y: .value("Distance", bucket.totals.distance / unit.metersPerUnit))
                    .foregroundStyle(selected == nil || selected?.start == bucket.start ? Color.track : Color.track.opacity(0.3))
                    .cornerRadius(3)
                    .accessibilityLabel(bucketLabel(bucket))
                    .accessibilityValue("\(RunFormat.distance(bucket.totals.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)")
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis { xAxis }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Color.line.opacity(0.6))
                    AxisValueLabel {
                        if let distance = value.as(Double.self) {
                            Text(distance.formatted(.number.precision(.fractionLength(0))))
                        }
                    }
                }
            }
            .frame(height: 150)
        }
    }

    private var xAxis: some AxisContent {
        let (component, count, format, centered): (Calendar.Component, Int, Date.FormatStyle, Bool) = switch period {
        case .week: (.day, 1, .dateTime.weekday(.narrow), true)
        case .month: (.day, 7, .dateTime.day(), false)
        case .year: (.month, 1, .dateTime.month(.narrow), true)
        case .all: (.year, 1, .dateTime.year(), true)
        }
        return AxisMarks(values: .stride(by: component, count: count)) { _ in
            AxisValueLabel(format: format, centered: centered)
        }
    }

    private func chartCaption(_ selected: StatsBucket?) -> String {
        guard let selected else {
            return switch period {
            case .week, .month: "Distance per day"
            case .year: "Distance per month"
            case .all: "Distance per year"
            }
        }
        let runs = selected.totals.runs
        let distance = "\(RunFormat.distance(selected.totals.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
        return "\(bucketLabel(selected)) · \(distance) · \(runs) \(runs == 1 ? "run" : "runs")"
    }

    private func bucketLabel(_ bucket: StatsBucket) -> String {
        switch period {
        case .week, .month: bucket.start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .year: bucket.start.formatted(.dateTime.month(.wide).year())
        case .all: bucket.start.formatted(.dateTime.year())
        }
    }

    // MARK: Yearly goal

    private func yearlyGoalRow(distance: Double, interval: DateInterval) -> some View {
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
            ProgressBar(progress: yearlyGoal > 0 ? done / yearlyGoal : 0)
            // A projection needs a few weeks of the year behind it to mean anything.
            if elapsed > 0.05, done > 0, done < yearlyGoal {
                let projected = done / elapsed
                Text(projected >= yearlyGoal
                     ? "On pace for \(Int(projected).formatted()) \(unit.distanceSymbol) this year"
                     : "\(Int((yearlyGoal - done).rounded(.up)).formatted()) \(unit.distanceSymbol) to go · on pace for \(Int(projected).formatted())")
                    .font(.caption)
                    .foregroundStyle(projected >= yearlyGoal ? Color.success : Color.inkMuted)
            } else if done >= yearlyGoal {
                Text("Goal reached").font(.caption.weight(.semibold)).foregroundStyle(.success)
            }
        }
        .padding(.top, Space.x1)
    }
}
