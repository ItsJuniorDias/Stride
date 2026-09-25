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
                    Label("Run complete", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(.success)

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
