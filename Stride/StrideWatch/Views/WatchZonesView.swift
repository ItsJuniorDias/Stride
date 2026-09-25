import SwiftUI
import StrideKit
import StrideUI

/// The current zone large, then time in each zone as compact bars.
struct WatchZonesView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x2) {
                if let zone = workout.currentZone {
                    HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                        Text("\(zone.rawValue)")
                            .font(.system(size: 40, weight: .heavy).width(.expanded))
                            .foregroundStyle(zone.color)
                        Text(zone.name)
                            .font(.headline)
                    }
                } else {
                    Text("Waiting for heart rate")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
                WatchZoneBars(seconds: workout.zoneSeconds)
            }
            .scenePadding()
        }
    }
}

/// Time in zones, highest zone on top, for the narrow Watch screen.
struct WatchZoneBars: View {
    let seconds: [HeartRateZone: TimeInterval]

    var body: some View {
        let longest = max(seconds.values.max() ?? 0, 1)
        VStack(spacing: Space.x1) {
            ForEach(HeartRateZone.allCases.reversed(), id: \.self) { zone in
                let time = seconds[zone] ?? 0
                HStack(spacing: Space.x2) {
                    Text("\(zone.rawValue)")
                        .font(.caption2.weight(.bold))
                        .frame(width: 12)
                    GeometryReader { geo in
                        Capsule()
                            .fill(zone.color)
                            .frame(width: max(geo.size.width * time / longest, time > 0 ? 4 : 0))
                    }
                    .frame(height: 8)
                    Text(RunFormat.duration(time))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(minWidth: 40, alignment: .trailing)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Zone \(zone.rawValue), \(zone.name), \(RunFormat.duration(time))")
            }
        }
    }
}
