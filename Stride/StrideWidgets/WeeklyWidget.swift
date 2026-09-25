import WidgetKit
import SwiftUI
import StrideKit
import StrideUI

struct WeeklyEntry: TimelineEntry {
    let date: Date
    /// nil until the app has written one.
    let snapshot: WidgetSnapshot?
}

struct WeeklyProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyEntry {
        WeeklyEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyEntry) -> Void) {
        completion(WeeklyEntry(date: .now, snapshot: WidgetStore.load() ?? (context.isPreview ? .placeholder : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetStore.load()
        // Drawn again at midnight: the day bars move on, and a new week starts from zero.
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(6 * 3_600)
        completion(Timeline(entries: [WeeklyEntry(date: now, snapshot: snapshot), WeeklyEntry(date: midnight, snapshot: snapshot)],
                            policy: .after(midnight)))
    }
}

/// This week's distance against the weekly goal, on the Home Screen and Lock Screen.
struct WeeklyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.weeklyKind, provider: WeeklyProvider()) { entry in
            WeeklyWidgetView(entry: entry)
                .widgetURL(StrideLink.progress.url)
        }
        .configurationDisplayName("This Week")
        .description("Your distance this week against your weekly goal.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

/// The week's numbers for one entry, in the runner's unit.
struct WeekFigures {
    let unit: UnitSystem
    let distance: Double
    let duration: TimeInterval
    let runs: Int
    let goal: Double
    let days: [Double]
    let streak: Int

    init(_ entry: WeeklyEntry) {
        let snapshot = entry.snapshot
        unit = snapshot?.unit ?? .metric
        let week = snapshot?.week(containing: entry.date) ?? (distance: 0, duration: 0, runs: 0)
        distance = week.distance / unit.metersPerUnit
        duration = week.duration
        runs = week.runs
        goal = snapshot?.weeklyGoal ?? 20
        days = snapshot?.days(ofWeekContaining: entry.date) ?? Array(repeating: 0, count: 7)
        streak = snapshot?.weekStreak(at: entry.date) ?? 0
    }

    var progress: Double { goal > 0 ? min(distance / goal, 1) : 0 }
    var reached: Bool { goal > 0 && distance >= goal }
    var distanceText: String { distance.formatted(.number.precision(.fractionLength(1))) }
    var goalText: String { "\(Int(goal)) \(unit.distanceSymbol)" }
    var runsText: String { runs == 0 ? "No runs yet" : "\(runs) \(runs == 1 ? "run" : "runs")" }
}

struct WeeklyWidgetView: View {
    let entry: WeeklyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if entry.snapshot == nil {
            // Before the app has run once there's no week to show, only a way in.
            noData
        } else {
            figures(WeekFigures(entry))
        }
    }

    @ViewBuilder private var noData: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "figure.run")
                .font(.title3.weight(.semibold))
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular, .accessoryInline:
            Label("Open Stride", systemImage: "figure.run")
                .containerBackground(for: .widget) { Color.clear }
        default:
            VStack(alignment: .leading, spacing: Space.x2) {
                Image(systemName: "figure.run").font(.title2.weight(.bold)).foregroundStyle(.track)
                Spacer()
                Text("Your week").font(.headline).foregroundStyle(.ink)
                Text("Open Stride to see it here.").font(.caption).foregroundStyle(.inkMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { Color.surfaceRaised }
        }
    }

    @ViewBuilder private func figures(_ week: WeekFigures) -> some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: week.progress) {
                Image(systemName: "figure.run")
            } currentValueLabel: {
                Text(week.distanceText).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Label("This week", systemImage: "figure.run")
                    .font(.caption.weight(.semibold))
                    .widgetAccentable()
                Text("\(week.distanceText) of \(week.goalText)")
                    .font(.headline)
                    .monospacedDigit()
                Gauge(value: week.progress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            Label("\(week.distanceText) of \(week.goalText) this week", systemImage: "figure.run")
                .containerBackground(for: .widget) { Color.clear }
        case .systemMedium:
            HStack(spacing: Space.x4) {
                ring(week).frame(width: 110, height: 110)
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text("This week").font(.headline).foregroundStyle(.ink)
                    Text("\(week.runsText) · \(RunFormat.duration(week.duration))")
                        .font(.caption)
                        .foregroundStyle(.inkMuted)
                    DayBars(days: week.days, date: entry.date)
                    if week.streak > 1 {
                        Label("\(week.streak) weeks in a row", systemImage: "flame.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.track)
                    }
                }
                Spacer(minLength: 0)
            }
            .containerBackground(for: .widget) { Color.surfaceRaised }
        default:
            VStack(alignment: .leading, spacing: Space.x2) {
                HStack {
                    Text("This week").font(.caption.weight(.semibold)).foregroundStyle(.inkMuted)
                    Spacer()
                    Image(systemName: "figure.run").font(.caption).foregroundStyle(.track)
                }
                ring(week).frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(week.runsText).font(.caption2).foregroundStyle(.inkMuted).frame(maxWidth: .infinity)
            }
            .containerBackground(for: .widget) { Color.surfaceRaised }
        }
    }

    private func ring(_ week: WeekFigures) -> some View {
        ProgressRing(progress: week.progress, lineWidth: 9) {
            VStack(spacing: 0) {
                Text(week.distanceText)
                    .font(.system(.title3, weight: .bold).width(.expanded))
                    .monospacedDigit()
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(.ink)
                Text("of \(week.goalText)")
                    .font(.caption2)
                    .foregroundStyle(week.reached ? Color.success : Color.inkMuted)
            }
        }
    }
}

/// A bar per day of the week, today's labeled in the brand color.
struct DayBars: View {
    let days: [Double]
    let date: Date

    var body: some View {
        let calendar = Calendar.current
        let peak = max(days.max() ?? 0, 1)
        let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, meters in
                let day = calendar.date(byAdding: .day, value: index, to: start) ?? start
                let isToday = calendar.isDate(day, inSameDayAs: date)
                VStack(spacing: 3) {
                    Capsule()
                        .fill(meters > 0 ? Color.track : Color.surfaceSunken)
                        .frame(width: 9, height: max(5, 34 * meters / peak))
                    Text(day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 9, weight: isToday ? .bold : .regular))
                        .foregroundStyle(isToday ? Color.track : Color.inkMuted)
                }
            }
        }
        .frame(height: 50, alignment: .bottom)
    }
}
