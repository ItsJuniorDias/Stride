import WidgetKit
import SwiftUI
import StrideKit
import StrideUI

struct WatchWeeklyEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct WatchWeeklyProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchWeeklyEntry {
        WatchWeeklyEntry(date: .now, snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchWeeklyEntry) -> Void) {
        completion(WatchWeeklyEntry(date: .now, snapshot: WidgetStore.load() ?? (context.isPreview ? .placeholder : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchWeeklyEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetStore.load()
        // A new week starts from zero at midnight on its first day.
        let midnight = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(6 * 3_600)
        completion(Timeline(entries: [WatchWeeklyEntry(date: now, snapshot: snapshot), WatchWeeklyEntry(date: midnight, snapshot: snapshot)],
                            policy: .after(midnight)))
    }
}

/// This week's distance against the goal, on the watch face and in the Smart Stack.
struct WatchWeeklyWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.weeklyKind, provider: WatchWeeklyProvider()) { entry in
            WatchWeeklyView(entry: entry)
        }
        .configurationDisplayName("This Week")
        .description("Your distance this week against your weekly goal.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

struct WatchWeeklyView: View {
    let entry: WatchWeeklyEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let snapshot = entry.snapshot {
            figures(snapshot)
        } else {
            // Nothing from iPhone yet.
            Image(systemName: "figure.run")
                .font(.title3.weight(.semibold))
                .foregroundStyle(.track)
                .widgetLabel { Text("Stride") }
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
    }

    @ViewBuilder private func figures(_ snapshot: WidgetSnapshot) -> some View {
        let unit = snapshot.unit
        let week = snapshot.week(containing: entry.date)
        let distance = week.distance / unit.metersPerUnit
        let goal = snapshot.weeklyGoal
        let progress = goal > 0 ? min(distance / goal, 1) : 0
        let distanceText = distance.formatted(.number.precision(.fractionLength(1)))
        switch family {
        case .accessoryCorner:
            Image(systemName: "figure.run")
                .font(.title3.weight(.semibold))
                .widgetAccentable()
                .widgetLabel {
                    Gauge(value: progress) { Text(unit.distanceSymbol) } currentValueLabel: { Text(distanceText) }
                        .tint(.track)
                }
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("This week", systemImage: "figure.run")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.track)
                    .widgetAccentable()
                Text("\(distanceText) of \(Int(goal)) \(unit.distanceSymbol)")
                    .font(.headline)
                    .monospacedDigit()
                Gauge(value: progress) { EmptyView() }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(.track)
                Text(week.runs == 0 ? "No runs yet" : "\(week.runs) \(week.runs == 1 ? "run" : "runs")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryInline:
            Label("\(distanceText) of \(Int(goal)) \(unit.distanceSymbol)", systemImage: "figure.run")
                .containerBackground(for: .widget) { Color.clear }
        default:
            Gauge(value: progress) {
                Image(systemName: "figure.run")
            } currentValueLabel: {
                Text(distanceText).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(.track)
            .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        }
    }
}

struct WatchStartEntry: TimelineEntry {
    let date: Date
}

struct WatchStartProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchStartEntry { WatchStartEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (WatchStartEntry) -> Void) { completion(WatchStartEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchStartEntry>) -> Void) {
        completion(Timeline(entries: [WatchStartEntry(date: .now)], policy: .never))
    }
}

/// Opens Stride on Apple Watch, ready to start a run.
struct WatchStartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.quickStartKind, provider: WatchStartProvider()) { _ in
            WatchStartView()
        }
        .configurationDisplayName("Start Run")
        .description("Open Stride to start a run.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct WatchStartView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Start a run", systemImage: "figure.run")
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryCorner:
            Image(systemName: "figure.run")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.track)
                .widgetAccentable()
                .widgetLabel("Run")
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
        default:
            Image(systemName: "figure.run")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.track)
                .widgetAccentable()
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .accessibilityLabel("Start a run")
        }
    }
}
