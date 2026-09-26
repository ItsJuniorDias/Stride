import SwiftUI
import StrideKit
import StrideUI

struct WatchSummaryView: View {
    @Environment(WorkoutManager.self) private var workout
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        ScrollView {
            if let run = workout.summary {
                VStack(alignment: .leading, spacing: Space.x3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Run complete", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.success)
                        if let name = run.workoutName {
                            Text(name)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(2)
                        }
                        if let cursor = workout.cursor {
                            Text(stepsDone(cursor))
                                .font(.caption)
                                .foregroundStyle(.inkMuted)
                        }
                    }

                    metric("Distance", RunFormat.distance(run.distance, unit: unit), unit.distanceSymbol)
                    metric("Time", RunFormat.duration(run.duration), nil)
                    metric("Avg pace", RunFormat.pace(RunFormat.paceSeconds(distance: run.distance, duration: run.duration, unit: unit)), unit.paceSymbol)
                    if let heartRate = run.averageHeartRate {
                        metric("Avg heart rate", "\(Int(heartRate))", "bpm")
                    }
                    metric("Calories", "\(Int(run.calories))", "kcal")

                    if !run.zones.isEmpty {
                        Text("Zones").metricLabelStyle()
                        WatchZoneBars(seconds: run.zones)
                    }

                    Text(workout.savedToHealth
                         ? "Saved to Apple Health. Your iPhone will get it when it's nearby."
                         : "Couldn't save to Apple Health. Your iPhone will still get this run.")
                        .font(.caption2)
                        .foregroundStyle(workout.savedToHealth ? Color.inkMuted : Color.warning)

                    Button {
                        workout.reset()
                    } label: {
                        Text("Done").foregroundStyle(.onTrack)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.track)
                }
                .scenePadding()
            }
        }
    }

    /// "All 8 intervals done", or how far the run got when it ended early.
    private func stepsDone(_ cursor: WorkoutCursor) -> String {
        let total = cursor.workout.runStepCount
        guard !cursor.isFinished else { return total > 1 ? "All \(total) intervals done" : "Workout complete" }
        let done = cursor.workout.steps.prefix(cursor.index).filter { $0.kind == .run }.count
        return "\(done) of \(total) \(total == 1 ? "interval" : "intervals") done"
    }

    private func metric(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).metricLabelStyle()
            HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                Text(value)
                    .font(.metricSmall)
                    .monospacedDigit()
                if let unit {
                    Text(unit)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.inkMuted)
                }
            }
        }
    }
}
