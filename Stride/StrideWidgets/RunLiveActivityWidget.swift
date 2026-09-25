import WidgetKit
import SwiftUI
import ActivityKit
import AppIntents
import StrideKit
import StrideUI

/// The run in progress on the Lock Screen, in the Dynamic Island and in Apple Watch's Smart Stack.
struct RunLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RunActivityAttributes.self) { context in
            RunLockScreenView(attributes: context.attributes, state: context.state, isStale: context.isStale)
                .activitySystemActionForegroundColor(.track)
        } dynamicIsland: { context in
            let state = context.state
            let unit = context.attributes.unit
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    IslandMetric(label: "Distance", value: RunFormat.distance(state.distance, unit: unit), unit: unit.distanceSymbol)
                        .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("TIME").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        RunClockText(state: state, isStale: context.isStale)
                            .font(.title2.weight(.bold).width(.expanded))
                            .monospacedDigit()
                    }
                    .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: Space.x3) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(context.isStale ? "Open Stride to see your run" : StatusText.line(state, unit: unit))
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            if let step = state.step {
                                StepText(state: state, step: step, unit: unit).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        RunControlToggle(state: state)
                    }
                    .padding(.horizontal, 4)
                }
            } compactLeading: {
                Image(systemName: state.status == .running ? "figure.run" : "pause.fill")
                    .foregroundStyle(.track)
            } compactTrailing: {
                RunClockText(state: state, isStale: context.isStale)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    // "1:02:03" needs more room than "12:34"; a timer's width doesn't adapt by itself.
                    .frame(width: state.elapsed >= 3_540 ? 64 : 44)
                    .foregroundStyle(.track)
            } minimal: {
                Image(systemName: state.status == .running ? "figure.run" : "pause.fill")
                    .foregroundStyle(.track)
            }
            .widgetURL(StrideLink.run.url)
            .keylineTint(.track)
        }
        .supplementalActivityFamilies([.small])
    }
}

/// Counts up on its own while running; the stopped time otherwise, or when the app has stopped
/// sending updates (stale).
struct RunClockText: View {
    let state: RunActivityAttributes.ContentState
    var isStale = false

    var body: some View {
        if let start = state.clockStart, state.status == .running, !isStale {
            Text(start, style: .timer)
        } else {
            Text(RunFormat.duration(state.elapsed))
        }
    }
}

/// "Run · 3 of 8 · 1:24" with a live countdown for timed steps.
struct StepText: View {
    let state: RunActivityAttributes.ContentState
    let step: String
    let unit: UnitSystem

    var body: some View {
        if let end = state.stepEnd, end > .now {
            (Text("\(step) · ") + Text(timerInterval: Date.now...end, countsDown: true))
        } else if let meters = state.stepRemaining {
            Text("\(step) · \(meters < 1_000 && unit == .metric ? "\(Int(meters.rounded(.up))) m" : "\(RunFormat.distance(meters, unit: unit)) \(unit.distanceSymbol)") left")
        } else {
            Text(step)
        }
    }
}

enum StatusText {
    /// "5'12" /km", or the state when not running.
    static func line(_ state: RunActivityAttributes.ContentState, unit: UnitSystem) -> String {
        switch state.status {
        case .running: "\(RunFormat.pace(state.pace)) \(unit.paceSymbol)"
        case .paused: "Paused"
        case .autoPaused: "Auto-paused"
        case .finished: "Run complete · \(RunFormat.pace(state.pace)) \(unit.paceSymbol)"
        }
    }
}

struct IslandMetric: View {
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.title2.weight(.bold).width(.expanded)).monospacedDigit()
                Text(unit).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }
}

/// Pause while running, resume while paused. Runs in the app, not here.
struct RunControlToggle: View {
    let state: RunActivityAttributes.ContentState

    var body: some View {
        switch state.status {
        case .running, .autoPaused:
            Button(intent: PauseRunIntent()) {
                Image(systemName: "pause.fill").font(.body.weight(.bold))
            }
            .tint(.track)
            .accessibilityLabel("Pause run")
        case .paused where state.resumeInApp:
            // A run picked up after the app was closed resumes from inside Stride.
            Link(destination: StrideLink.run.url) {
                Label("Open", systemImage: "play.fill").font(.subheadline.weight(.bold))
            }
            .tint(.track)
            .accessibilityLabel("Open Stride to resume")
        case .paused:
            Button(intent: ResumeRunIntent()) {
                Image(systemName: "play.fill").font(.body.weight(.bold))
            }
            .tint(.track)
            .accessibilityLabel("Resume run")
        case .finished:
            EmptyView()
        }
    }
}

struct RunLockScreenView: View {
    let attributes: RunActivityAttributes
    let state: RunActivityAttributes.ContentState
    var isStale = false
    @Environment(\.activityFamily) private var family

    var body: some View {
        let unit = attributes.unit
        if family == .small {
            // Apple Watch's Smart Stack.
            VStack(alignment: .leading, spacing: 2) {
                Label(state.status == .running ? "Running" : StatusText.line(state, unit: unit), systemImage: "figure.run")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.track)
                RunClockText(state: state, isStale: isStale)
                    .font(.title3.weight(.bold).width(.expanded))
                    .monospacedDigit()
                Text("\(RunFormat.distance(state.distance, unit: unit)) \(unit.distanceSymbol)")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: Space.x3) {
                HStack {
                    Label(attributes.title, systemImage: "figure.run")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.track)
                        .lineLimit(1)
                    Spacer()
                    if isStale {
                        Text("Not updating")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Space.x2)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    } else if state.status != .running {
                        Text(state.status == .finished ? "Finished" : state.status == .paused ? "Paused" : "Auto-paused")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, Space.x2)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TIME").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        RunClockText(state: state, isStale: isStale)
                            .font(.system(size: 34, weight: .heavy).width(.expanded))
                            .monospacedDigit()
                            .minimumScaleFactor(0.7)
                    }
                    Spacer(minLength: Space.x2)
                    IslandMetric(label: "Distance", value: RunFormat.distance(state.distance, unit: unit), unit: unit.distanceSymbol)
                    Spacer(minLength: Space.x2)
                    IslandMetric(label: state.status == .running ? "Pace" : "Avg pace", value: RunFormat.pace(state.pace), unit: unit.paceSymbol)
                }
                if state.step != nil || state.status != .finished {
                    HStack {
                        if let step = state.step {
                            StepText(state: state, step: step, unit: unit)
                                .font(.subheadline.weight(.medium))
                                .monospacedDigit()
                        }
                        Spacer()
                        RunControlToggle(state: state)
                    }
                }
            }
            .padding(Space.x4)
        }
    }
}
