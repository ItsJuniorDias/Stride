import WidgetKit
import SwiftUI
import AppIntents
import StrideKit
import StrideUI

struct QuickStartEntry: TimelineEntry {
    let date: Date
}

struct QuickStartProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuickStartEntry { QuickStartEntry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (QuickStartEntry) -> Void) { completion(QuickStartEntry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuickStartEntry>) -> Void) {
        completion(Timeline(entries: [QuickStartEntry(date: .now)], policy: .never))
    }
}

/// Opens Stride on the Run tab, ready to start.
struct QuickStartWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetStore.quickStartKind, provider: QuickStartProvider()) { _ in
            QuickStartView()
                .widgetURL(StrideLink.run.url)
        }
        .configurationDisplayName("Quick Start")
        .description("Jump straight to starting a run.")
        .supportedFamilies([.accessoryCircular, .systemSmall])
    }
}

struct QuickStartView: View {
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if family == .accessoryCircular {
            Image(systemName: "figure.run")
                .font(.title2.weight(.semibold))
                .widgetAccentable()
                .containerBackground(for: .widget) { AccessoryWidgetBackground() }
                .accessibilityLabel("Start a run")
        } else {
            VStack(alignment: .leading, spacing: Space.x2) {
                Image(systemName: "figure.run")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.onTrack)
                    .frame(width: 48, height: 48)
                    .background(Color.track, in: Circle())
                Spacer()
                Text("Start a run").font(.headline).foregroundStyle(.ink)
                Text("Stride").font(.caption).foregroundStyle(.inkMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(for: .widget) { Color.surfaceRaised }
        }
    }
}

/// Control Center, the Lock Screen and the Action button: starts a run after the countdown.
struct StartRunControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "StrideStartRunControl") {
            ControlWidgetButton(action: StartRunIntent()) {
                Label("Start Run", systemImage: "figure.run")
            }
        }
        .displayName("Start Run")
        .description("Starts a run in Stride after a 3-second countdown.")
    }
}
