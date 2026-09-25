import SwiftUI
import StrideKit
import StrideUI

/// One metric per row, time first, heart rate tinted by its zone.
struct WatchMetricsView: View {
    @Environment(WorkoutManager.self) private var workout
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = workout.elapsedTime(at: context.date)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(RunFormat.duration(elapsed))
                    .font(.system(size: 40, weight: .heavy).width(.expanded))
                    .monospacedDigit()
                    .foregroundStyle(workout.phase == .paused ? Color.inkMuted : Color.track)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)

                row(RunFormat.distance(workout.distance, unit: unit), unit: unit.distanceSymbol.uppercased())
                row(RunFormat.pace(workout.currentPace(unit: unit, at: context.date)), unit: unit.paceSymbol.uppercased())

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

                if let progress = workout.goalProgress(at: context.date) {
                    ProgressView(value: min(progress, 1))
                        .tint(progress >= 1 ? Color.success : Color.track)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .scenePadding()
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
