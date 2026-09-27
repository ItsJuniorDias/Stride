import SwiftUI
import StrideKit
import StrideUI

/// The current zone large in its color with its name, heart rate and range, the zone scale with a
/// tick at the heart rate, then time in each zone.
struct WatchZonesView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        let zone = workout.currentZone
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Heart rate")
                    .watchFont(13, .semibold)
                    .foregroundStyle(.inkMuted)
                    .frame(minHeight: 22)
                    .accessibilityAddTraits(.isHeader)

                current(zone: zone)
                    .padding(.top, Space.x1)

                ZoneScale(highlighted: workout.heartRate == nil ? nil : zone,
                          marker: workout.heartRate.map { scalePosition(of: $0) })
                    .padding(.vertical, 3)
                    .padding(.top, 5)

                WatchOverline("Time in zones")
                    .padding(.top, 10)
                ZoneTimeList(seconds: workout.zoneSeconds, style: .compact, current: zone)
                    .padding(.top, 6)
            }
            .padding(.horizontal, Space.x4)
            // Clear of the page dots.
            .padding(.bottom, Space.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    /// "3", "Aerobic", "148 bpm · 133–151".
    @ViewBuilder private func current(zone: HeartRateZone?) -> some View {
        if let heartRate = workout.heartRate {
            HStack(spacing: 10) {
                Text(zone.map { "\($0.rawValue)" } ?? RunFormat.empty)
                    .font(.watchMetric(52, weight: .heavy))
                    .foregroundStyle(zone?.color ?? Color.inkMuted)
                    .lineLimit(1)
                    .fixedSize()
                VStack(alignment: .leading, spacing: 1) {
                    Text(zone?.name ?? "Below zone 1")
                        .watchFont(17, .semibold)
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                        Text("\(Int(heartRate))")
                            .font(.watchMetric(15))
                            .foregroundStyle(.ink)
                        Text("bpm · \(range(of: zone))")
                            .watchFont(12, digits: true)
                            .foregroundStyle(.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }
            .frame(minHeight: 48)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(zone.map { "Zone \($0.rawValue), \($0.name.lowercased()), \(Int(heartRate)) beats per minute" }
                                ?? "Below zone 1, \(Int(heartRate)) beats per minute")
        } else {
            HStack(spacing: 10) {
                Text(RunFormat.empty)
                    .font(.watchMetric(52, weight: .heavy))
                    .foregroundStyle(.inkMuted)
                    .fixedSize()
                    .accessibilityHidden(true)
                Text("Waiting for heart rate")
                    .watchFont(13)
                    .foregroundStyle(.inkMuted)
                    .lineLimit(2)
            }
            .frame(minHeight: 48)
        }
    }

    /// The zone's heart rates from the runner's max: "133–151", or "under 95" below zone 1.
    private func range(of zone: HeartRateZone?) -> String {
        let max = workout.maxHeartRate
        guard let zone else { return "under \(Int((HeartRateZone.recovery.lowerBound * max).rounded()))" }
        let lower = Int((zone.lowerBound * max).rounded())
        let upper = HeartRateZone(rawValue: zone.rawValue + 1).map { Int(($0.lowerBound * max).rounded()) - 1 }
            ?? Int(max.rounded())
        return "\(lower)–\(upper)"
    }

    /// Where a heart rate sits along the five equal zone blocks, 0…1.
    private func scalePosition(of heartRate: Double) -> Double {
        let max = workout.maxHeartRate
        guard max > 0, let zone = HeartRateZone.zone(for: heartRate, maxHeartRate: max) else { return 0 }
        let upper = zone == .maximum ? 1 : zone.lowerBound + 0.1
        let within = (heartRate / max - zone.lowerBound) / (upper - zone.lowerBound)
        return (Double(zone.rawValue - 1) + min(Swift.max(within, 0), 1)) / 5
    }
}
