import SwiftUI
import StrideKit

/// Time spent in each heart-rate zone, highest zone on top.
public struct ZoneBars: View {
    let seconds: [HeartRateZone: TimeInterval]

    public init(seconds: [HeartRateZone: TimeInterval]) {
        self.seconds = seconds
    }

    public var body: some View {
        let longest = max(seconds.values.max() ?? 0, 1)
        VStack(spacing: Space.x2) {
            ForEach(HeartRateZone.allCases.reversed(), id: \.self) { zone in
                let time = seconds[zone] ?? 0
                HStack(spacing: Space.x3) {
                    Text("\(zone.rawValue)")
                        .font(.system(size: 13, weight: .bold).width(.expanded))
                        .frame(width: 20, alignment: .leading)
                    Text(zone.name).frame(width: 92, alignment: .leading)
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: Radius.sm)
                            .fill(zone.color)
                            .frame(width: max(geo.size.width * time / longest, time > 0 ? 6 : 0))
                    }
                    .frame(height: 12)
                    Text(RunFormat.duration(time))
                        .foregroundStyle(.inkMuted)
                        .frame(width: 52, alignment: .trailing)
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.ink)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Space.x4)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
    }
}
