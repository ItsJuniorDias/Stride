import SwiftUI
import StrideKit
import StrideUI

/// After the run: "Run complete" and how it went against its goal, the distance large, time, pace,
/// heart rate and calories, time in zones, whether Apple Health has it, and Done pinned at the bottom.
struct WatchSummaryView: View {
    @Environment(WorkoutManager.self) private var workout
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        ScrollView {
            if let run = workout.summary {
                VStack(alignment: .leading, spacing: 0) {
                    header(run)

                    WatchOverline("Distance")
                        .padding(.top, Space.x3)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(RunFormat.distance(run.distance, unit: unit))
                            .font(.watchMetric(44, weight: .heavy))
                            .tracking(-0.4)
                            .foregroundStyle(.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        WatchUnitLabel(unit.distanceSymbol)
                    }
                    .padding(.top, 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Distance")
                    .accessibilityValue(WatchSpeech.distance(run.distance, unit: unit))

                    stats(run)
                        .padding(.top, Space.x3)

                    if !run.zones.isEmpty {
                        WatchOverline("Zones")
                            .padding(.top, Space.x4)
                        ZoneTimeList(seconds: run.zones, style: .compact)
                            .padding(.top, 6)
                    }

                    healthNote
                        .padding(.top, 14)
                }
                .padding(.horizontal, Space.x4)
                .padding(.bottom, Space.x2)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button("Done") { workout.reset() }
                .buttonStyle(WatchCapsuleButtonStyle(fill: .track, foreground: .onTrack))
                .padding(.horizontal, 18)
                .padding(.top, Space.x5)
                .background {
                    // The numbers fade out under the button.
                    LinearGradient(stops: [.init(color: Color.surface.opacity(0), location: 0),
                                           .init(color: Color.surface, location: 0.3)],
                                   startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea()
                }
        }
    }

    // MARK: Parts

    /// The check and "Run complete" in success, then the goal or the workout underneath.
    private func header(_ run: RunTransfer) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
                Text("Run complete")
                    .watchFont(15, .semibold)
            }
            .foregroundStyle(.success)
            .frame(minHeight: 22)
            .accessibilityAddTraits(.isHeader)

            ForEach(outcome(of: run), id: \.self) { line in
                Text(line)
                    .watchFont(12)
                    .foregroundStyle(.inkMuted)
                    .lineLimit(2)
            }
        }
    }

    /// "5 km goal reached", "64% of your 5 km goal", the workout and its intervals, or the run's name.
    private func outcome(of run: RunTransfer) -> [String] {
        let goal = workout.goal
        switch goal.type {
        case .intervals:
            return [run.workoutName ?? goal.title] + (workout.cursor.map { [stepsDone($0)] } ?? [])
        case .distance, .time:
            let progress: Double? = if let target = goal.distance, target > 0 {
                run.distance / target
            } else if let target = goal.duration, target > 0 {
                run.duration / target
            } else {
                nil
            }
            guard let progress else { return [goal.title] }
            return progress >= 1
                ? ["\(goal.title) reached"]
                : ["\(Int((progress * 100).rounded(.down)))% of your \(goal.title)"]
        case .free:
            return [Run.timeOfDayTitle(for: run.startDate)]
        }
    }

    /// "All 8 intervals done", or how far the run got when it ended early.
    private func stepsDone(_ cursor: WorkoutCursor) -> String {
        let total = cursor.workout.runStepCount
        guard !cursor.isFinished else { return total > 1 ? "All \(total) intervals done" : "Workout complete" }
        let done = cursor.workout.steps.prefix(cursor.index).filter { $0.kind == .run }.count
        return "\(done) of \(total) \(total == 1 ? "interval" : "intervals") done"
    }

    /// Time, average pace, average heart rate and calories in two equal columns.
    private func stats(_ run: RunTransfer) -> some View {
        let pace = RunFormat.paceSeconds(distance: run.distance, duration: run.duration, unit: unit)
        return VStack(alignment: .leading, spacing: Space.x4) {
            HStack(alignment: .top, spacing: 10) {
                stat("Time", RunFormat.duration(run.duration), nil,
                     spoken: WatchSpeech.duration(run.duration))
                stat("Avg pace", RunFormat.pace(pace), unit.paceSymbol,
                     spoken: WatchSpeech.pace(pace, unit: unit), spokenLabel: "Average pace")
            }
            HStack(alignment: .top, spacing: 10) {
                stat("Avg HR", run.averageHeartRate.map { "\(Int($0))" } ?? RunFormat.empty, "bpm",
                     spoken: run.averageHeartRate.map { "\(Int($0)) beats per minute" } ?? "Unavailable",
                     spokenLabel: "Average heart rate")
                stat("Calories", "\(Int(run.calories))", "kcal",
                     spoken: "\(Int(run.calories)) kilocalories")
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String?, spoken: String,
                      spokenLabel: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            WatchOverline(label)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.watchMetric(20))
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let unit {
                    Text(unit)
                        .watchFont(11, .medium)
                        .foregroundStyle(.inkMuted)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel ?? label)
        .accessibilityValue(spoken)
    }

    /// Saved to Apple Health, or a warning that it wasn't (iPhone still gets the run).
    private var healthNote: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: workout.savedToHealth ? "heart.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .padding(.top, 1)
                .accessibilityHidden(true)
            Text(workout.savedToHealth
                 ? "Saved to Apple Health. Your iPhone will get it when it's nearby."
                 : "Couldn't save to Apple Health. Your iPhone will still get this run.")
                .watchFont(12)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(workout.savedToHealth ? Color.inkMuted : Color.warning)
    }
}
