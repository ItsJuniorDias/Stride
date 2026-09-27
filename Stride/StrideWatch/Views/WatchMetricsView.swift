import Foundation
import SwiftUI
import StrideKit
import StrideUI

/// The numbers while running. A goal or free run: what it's for, the big clock, distance, pace and
/// heart rate tinted by its zone, then how far is left to the goal. An interval run: the clock and
/// distance small on top, the current step in a card, then pace and heart rate. Scrolls only when a
/// small Watch or a large text size needs the room.
struct WatchMetricsView: View {
    @Environment(WorkoutManager.self) private var workout
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        ScrollView {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Group {
                    if let cursor = workout.cursor {
                        intervalPage(cursor, at: context.date)
                    } else {
                        goalPage(at: context.date)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var isPaused: Bool { workout.phase == .paused }

    // MARK: Goal and free runs

    private func goalPage(at date: Date) -> some View {
        let elapsed = workout.elapsedTime(at: date)
        return VStack(alignment: .leading, spacing: 0) {
            WatchRunStatus(title: workout.goal.title, isPaused: isPaused)

            Text(RunFormat.duration(elapsed))
                .font(.watchMetric(44, weight: .heavy))
                .tracking(-0.4)
                .foregroundStyle(isPaused ? Color.inkMuted : Color.track)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.top, Space.x1)
                .accessibilityLabel("Time \(WatchSpeech.duration(elapsed))\(isPaused ? ", paused" : "")")

            VStack(alignment: .leading, spacing: 2) {
                distanceRow
                paceRow(at: date)
                WatchHeartRateRow(heartRate: workout.heartRate, zone: workout.currentZone)
            }
            .padding(.top, 6)

            if let progress = workout.goalProgress(at: date) {
                goalProgress(progress, elapsed: elapsed)
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, Space.x4)
        // Clear of the page dots.
        .padding(.bottom, Space.x5)
    }

    /// The goal bar in the data color (success once reached) and what's left: "0.79 km to go".
    private func goalProgress(_ progress: Double, elapsed: TimeInterval) -> some View {
        let reached = progress >= 1
        let left = leftToGo(elapsed: elapsed)
        return VStack(alignment: .leading, spacing: Space.x1) {
            TrackBar(progress: min(progress, 1), tint: reached ? .success : .lane, height: 6, track: .surfaceRaised)
            Text(reached ? "Goal reached" : "\(left) to go")
                .watchFont(12, digits: true)
                .foregroundStyle(reached ? Color.success : Color.inkMuted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(workout.goal.title)
        .accessibilityValue(reached ? "Goal reached" : "\(Int((progress * 100).rounded())) percent, \(left) to go")
    }

    /// Distance in the runner's unit, or time.
    private func leftToGo(elapsed: TimeInterval) -> String {
        if let target = workout.goal.distance, target > 0 {
            return "\(RunFormat.distance(max(target - workout.distance, 0), unit: unit)) \(unit.distanceSymbol)"
        }
        if let target = workout.goal.duration, target > 0 {
            // Rounded up: it reads 0:00 only once the goal is reached.
            return RunFormat.duration(max(target - elapsed, 0).rounded(.up))
        }
        return ""
    }

    // MARK: Interval runs

    private func intervalPage(_ cursor: WorkoutCursor, at date: Date) -> some View {
        let elapsed = workout.elapsedTime(at: date)
        return VStack(alignment: .leading, spacing: 0) {
            // The whole run's time and distance, small, so they aren't read as the step's.
            HStack(spacing: 6) {
                Text(RunFormat.duration(elapsed))
                    .font(.watchMetric(15, weight: .heavy))
                    .foregroundStyle(isPaused ? Color.inkMuted : Color.track)
                    .fixedSize()
                if isPaused {
                    Text("Paused")
                        .watchFont(13, .semibold)
                        .foregroundStyle(.warning)
                } else {
                    Text("\(RunFormat.distance(workout.distance, unit: unit)) \(unit.distanceSymbol)")
                        .watchFont(13, .semibold, digits: true)
                        .foregroundStyle(.inkMuted)
                }
            }
            .lineLimit(1)
            .frame(minHeight: 22)
            .padding(.leading, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Total time \(WatchSpeech.duration(elapsed)), "
                                + (isPaused ? "paused" : WatchSpeech.distance(workout.distance, unit: unit)))

            WatchStepCard(cursor: cursor, remaining: workout.stepRemaining(at: date),
                          progress: workout.stepProgress(at: date), paceStatus: workout.paceStatus,
                          isPaused: isPaused, unit: unit)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 0) {
                paceRow(at: date)
                WatchHeartRateRow(heartRate: workout.heartRate, zone: workout.currentZone)
            }
            .padding(.horizontal, 6)
            .padding(.top, 6)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, Space.x5)
    }

    // MARK: Rows

    private var distanceRow: some View {
        WatchMetricRow(value: RunFormat.distance(workout.distance, unit: unit), unit: unit.distanceSymbol,
                       accessibilityText: WatchSpeech.distance(workout.distance, unit: unit))
    }

    private func paceRow(at date: Date) -> some View {
        let pace = workout.currentPace(unit: unit, at: date)
        return WatchMetricRow(value: RunFormat.pace(pace), unit: unit.paceSymbol,
                              accessibilityText: WatchSpeech.pace(pace, unit: unit))
    }
}

/// The current workout step on a raised card: its color dot and name ("Run · 3 of 5"), what's left
/// of it large, a bar through it, what comes next, and the target-pace cue when it has one.
struct WatchStepCard: View {
    let cursor: WorkoutCursor
    let remaining: WorkoutStep.Goal?
    let progress: Double
    let paceStatus: PaceGuard.Status?
    let isPaused: Bool
    let unit: UnitSystem

    var body: some View {
        Group {
            if let step = cursor.currentStep {
                stepCard(step)
            } else {
                Label("Workout complete", systemImage: "checkmark.circle.fill")
                    .watchFont(15, .semibold)
                    .foregroundStyle(.success)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
        }
        .padding(EdgeInsets(top: 8, leading: 12, bottom: 9, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchCard()
    }

    private func stepCard(_ step: WorkoutStep) -> some View {
        let tint = step.kind.color
        let left = remainingParts
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                Text(title(of: step))
                    .watchFont(11, .bold)
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(tint)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(left.value)
                    .font(.watchMetric(36, weight: .heavy))
                    .tracking(-0.3)
                    .foregroundStyle(isPaused ? Color.inkMuted : Color.ink)
                    .contentTransition(.numericText(countsDown: true))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !left.unit.isEmpty {
                    WatchUnitLabel(left.unit)
                }
            }
            .padding(.top, 2)

            TrackBar(progress: progress, tint: tint, height: 4, track: .surfaceSunken)
                .padding(.top, 5)

            if let next = cursor.nextStep {
                Text(nextText(next))
                    .watchFont(12, digits: true)
                    .foregroundStyle(.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.top, 5)
            }
            if let paceStatus {
                paceLine(paceStatus)
                    .padding(.top, 2)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenCard(step))
    }

    /// "Run · 3 of 8", as on iPhone.
    private func title(of step: WorkoutStep) -> String {
        if let number = cursor.workout.runNumber(of: step), cursor.workout.runStepCount > 1 {
            return "\(step.kind.title) · \(number) of \(cursor.workout.runStepCount)"
        }
        return step.kind.title
    }

    /// "320" and "m left", "1:24" and "left".
    private var remainingParts: (value: String, unit: String) {
        switch remaining {
        // Rounded up: the card reads 0 only once the step is actually done.
        case .time(let seconds):
            (RunFormat.duration(seconds.rounded(.up)), "left")
        case .distance(let meters):
            if meters < 1_000 && unit == .metric {
                ("\(Int(meters.rounded(.up)))", "m left")
            } else {
                (RunFormat.distance((meters / unit.metersPerUnit * 100).rounded(.up) / 100 * unit.metersPerUnit, unit: unit),
                 "\(unit.distanceSymbol) left")
            }
        case nil:
            (RunFormat.empty, "")
        }
    }

    /// "Next: Recover 2:00", "Next: Run 4 of 5 · 800 m".
    private func nextText(_ next: WorkoutStep) -> String {
        if let number = cursor.workout.runNumber(of: next), cursor.workout.runStepCount > 1 {
            return "Next: \(next.kind.title) \(number) of \(cursor.workout.runStepCount) · \(goalText(next.goal))"
        }
        return "Next: \(next.kind.title) \(goalText(next.goal))"
    }

    private func goalText(_ goal: WorkoutStep.Goal) -> String {
        switch goal {
        case .time(let seconds): seconds < 60 ? "\(Int(seconds)) s" : RunFormat.duration(seconds)
        case .distance(let meters): meters < 1_000 && unit == .metric ? "\(Int(meters)) m" : "\(RunFormat.distance(meters, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
        }
    }

    /// Words first; the color and the arrow only reinforce them.
    private func paceLine(_ status: PaceGuard.Status) -> some View {
        let line: (text: String, symbol: String, tint: Color) = switch status {
        case .onPace: ("On target pace", "checkmark", Color.success)
        case .tooSlow(let seconds): ("Speed up · \(Int(seconds.rounded())) s behind", "arrow.up", Color.warning)
        case .tooFast(let seconds): ("Ease off · \(Int(seconds.rounded())) s ahead", "arrow.down", Color.lane)
        }
        return HStack(spacing: Space.x1) {
            Image(systemName: line.symbol)
                .font(.system(size: 11, weight: .bold))
            Text(line.text)
                .watchFont(12, .semibold, digits: true)
                .lineLimit(2)
        }
        .foregroundStyle(line.tint)
    }

    // MARK: VoiceOver

    /// "Run 3 of 5, 320 meters left. Speed up, 7 seconds per kilometer behind target pace.
    /// Next: recover, 2 minutes."
    private func spokenCard(_ step: WorkoutStep) -> String {
        var name = step.kind.title
        if let number = cursor.workout.runNumber(of: step), cursor.workout.runStepCount > 1 {
            name += " \(number) of \(cursor.workout.runStepCount)"
        }
        var parts = ["\(name), \(spokenRemaining) left\(isPaused ? ", paused" : "")."]
        if let paceStatus {
            let perUnit = "per \(WatchSpeech.unitName(unit, plural: false))"
            switch paceStatus {
            case .onPace: parts.append("On target pace.")
            case .tooSlow(let seconds): parts.append("Speed up, \(Int(seconds.rounded())) seconds \(perUnit) behind target pace.")
            case .tooFast(let seconds): parts.append("Ease off, \(Int(seconds.rounded())) seconds \(perUnit) ahead of target pace.")
            }
        }
        if let next = cursor.nextStep {
            parts.append("Next: \(next.kind.title.lowercased()), \(spokenGoal(next.goal)).")
        }
        return parts.joined(separator: " ")
    }

    private var spokenRemaining: String {
        switch remaining {
        case .time(let seconds): WatchSpeech.duration(seconds.rounded(.up))
        case .distance(let meters): spokenGoal(.distance(meters.rounded(.up)))
        case nil: "nothing"
        }
    }

    private func spokenGoal(_ goal: WorkoutStep.Goal) -> String {
        switch goal {
        case .time(let seconds):
            WatchSpeech.duration(seconds)
        case .distance(let meters):
            meters < 1_000 && unit == .metric
                ? "\(Int(meters)) meters"
                : "\(RunFormat.distance(meters, unit: unit)) \(WatchSpeech.unitName(unit, plural: true))"
        }
    }
}
