import SwiftUI
import StrideKit
import StrideUI

/// One metric per row, time first, heart rate tinted by its zone. An interval run puts its current
/// step on top instead of the big clock, and scrolls when the rows don't fit a small Watch.
struct WatchMetricsView: View {
    @Environment(WorkoutManager.self) private var workout
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if let cursor = workout.cursor {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        WatchStepCard(cursor: cursor, remaining: workout.stepRemaining(at: context.date),
                                      progress: workout.stepProgress(at: context.date),
                                      paceStatus: workout.paceStatus, isPaused: workout.phase == .paused, unit: unit)
                            .padding(.bottom, Space.x1)
                        // The whole run's time, labeled so it isn't read as the step's.
                        row(RunFormat.duration(workout.elapsedTime(at: context.date)), unit: "TOTAL")
                        rows(at: context.date)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .scenePadding()
                }
            } else {
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(RunFormat.duration(workout.elapsedTime(at: context.date)))
                        .font(.system(size: 40, weight: .heavy).width(.expanded))
                        .monospacedDigit()
                        .foregroundStyle(workout.phase == .paused ? Color.inkMuted : Color.track)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)

                    rows(at: context.date)

                    if let progress = workout.goalProgress(at: context.date) {
                        ProgressView(value: min(progress, 1))
                            .tint(progress >= 1 ? Color.success : Color.track)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .scenePadding()
            }
        }
    }

    /// Distance, pace and heart rate.
    @ViewBuilder private func rows(at date: Date) -> some View {
        row(RunFormat.distance(workout.distance, unit: unit), unit: unit.distanceSymbol.uppercased())
        row(RunFormat.pace(workout.currentPace(unit: unit, at: date)), unit: unit.paceSymbol.uppercased())

        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Text(workout.heartRate.map { "\(Int($0))" } ?? "--")
                .font(.metricSmall)
                .monospacedDigit()
            Image(systemName: "heart.fill")
                .font(.caption)
                .foregroundStyle(workout.currentZone?.color ?? Color.inkMuted)
            if let zone = workout.currentZone {
                Text("Z\(zone.rawValue)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(zone.color)
            }
        }
    }

    private func row(_ value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Text(value)
                .font(.metricSmall)
                .monospacedDigit()
            Text(unit)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.inkMuted)
        }
    }
}

/// The current workout step: what it is, what's left of it, how far through, and what comes next.
struct WatchStepCard: View {
    let cursor: WorkoutCursor
    let remaining: WorkoutStep.Goal?
    let progress: Double
    let paceStatus: PaceGuard.Status?
    let isPaused: Bool
    let unit: UnitSystem

    var body: some View {
        if let step = cursor.currentStep {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.x1) {
                    Circle()
                        .fill(color(of: step))
                        .frame(width: 8, height: 8)
                    Text(title(of: step))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(color(of: step))
                        .lineLimit(1)
                }
                Text(remainingText)
                    .font(.system(size: 36, weight: .heavy).width(.expanded))
                    .monospacedDigit()
                    .foregroundStyle(isPaused ? Color.inkMuted : Color.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .contentTransition(.numericText(countsDown: true))
                ProgressBar(progress: progress, tint: color(of: step), height: 4)
                    .padding(.vertical, 2)
                if let next = cursor.nextStep {
                    Text("Next: \(next.kind.title) \(goalText(next.goal))")
                        .font(.caption2)
                        .foregroundStyle(.inkMuted)
                        .lineLimit(1)
                }
                if let paceStatus {
                    paceLine(paceStatus)
                }
            }
            .accessibilityElement(children: .combine)
        } else {
            Label("Workout complete", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.success)
        }
    }

    private func color(of step: WorkoutStep) -> Color {
        switch step.kind {
        case .run: .track
        case .recover: .lane
        case .warmup, .cooldown: .inkMuted
        }
    }

    /// "Run · 3 of 8", as on iPhone.
    private func title(of step: WorkoutStep) -> String {
        if let number = cursor.workout.runNumber(of: step), cursor.workout.runStepCount > 1 {
            return "\(step.kind.title) · \(number) of \(cursor.workout.runStepCount)"
        }
        return step.kind.title
    }

    private var remainingText: String {
        switch remaining {
        // Rounded up: the card reads 0 only once the step is actually done.
        case .time(let seconds): RunFormat.duration(seconds.rounded(.up))
        case .distance(let meters):
            if meters < 1_000 && unit == .metric {
                "\(Int(meters.rounded(.up))) m"
            } else {
                "\(RunFormat.distance((meters / unit.metersPerUnit * 100).rounded(.up) / 100 * unit.metersPerUnit, unit: unit)) \(unit.distanceSymbol)"
            }
        case nil: RunFormat.empty
        }
    }

    private func goalText(_ goal: WorkoutStep.Goal) -> String {
        switch goal {
        case .time(let seconds): seconds < 60 ? "\(Int(seconds)) s" : RunFormat.duration(seconds)
        case .distance(let meters): meters < 1_000 && unit == .metric ? "\(Int(meters)) m" : "\(RunFormat.distance(meters, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
        }
    }

    /// Words first; the color only reinforces them.
    private func paceLine(_ status: PaceGuard.Status) -> some View {
        let line: (text: String, tint: Color) = switch status {
        case .onPace: ("On target pace", Color.success)
        case .tooSlow(let seconds): ("Speed up · \(Int(seconds.rounded())) s\(unit.paceSymbol) behind", Color.warning)
        case .tooFast(let seconds): ("Ease off · \(Int(seconds.rounded())) s\(unit.paceSymbol) ahead", Color.lane)
        }
        return Text(line.text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(line.tint)
            .lineLimit(2)
    }
}
