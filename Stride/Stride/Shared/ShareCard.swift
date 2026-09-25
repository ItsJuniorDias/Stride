import SwiftUI
import StrideKit
import StrideUI

/// A 4:5 image of a run for social media: the route large, the numbers under it, always on the
/// dark asphalt palette so it looks the same whichever theme the runner uses.
struct ShareCardView: View {
    let title: String
    let date: Date
    let distance: Double
    let duration: TimeInterval
    let elevationGain: Double
    let coordinates: [Coordinate]
    let unit: UnitSystem

    // Fixed Dark-theme values of the design tokens: surface, track, ink, ink-muted, line.
    private let background = Color(red: 0x10 / 255, green: 0x14 / 255, blue: 0x19 / 255)
    private let track = Color(red: 1, green: 0x6B / 255, blue: 0x47 / 255)
    private let ink = Color(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF0 / 255)
    private let muted = Color(red: 0x9B / 255, green: 0xA5 / 255, blue: 0xB3 / 255)
    private let line = Color(red: 0x3A / 255, green: 0x44 / 255, blue: 0x52 / 255)

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("STRIDE")
                    .font(.system(size: 15, weight: .heavy).width(.expanded))
                    .tracking(1.5)
                    .foregroundStyle(track)
                Spacer()
                Text(date.formatted(.dateTime.day().month(.abbreviated).year()))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(muted)
            }

            Group {
                if coordinates.count > 1 {
                    RouteShape(coordinates: coordinates)
                        .stroke(track, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
                        .padding(8)
                } else {
                    Image(systemName: "figure.run")
                        .font(.system(size: 72, weight: .bold))
                        .foregroundStyle(track)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 160)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1)
                    .foregroundStyle(muted)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(RunFormat.distance(distance, unit: unit))
                        .font(.system(size: 76, weight: .heavy).width(.expanded))
                        .monospacedDigit()
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                    Text(unit.distanceSymbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(muted)
                }
                .foregroundStyle(ink)
            }

            Rectangle().fill(line).frame(height: 1)

            HStack(spacing: 0) {
                stat("Time", RunFormat.duration(duration), nil)
                stat("Avg pace", RunFormat.pace(RunFormat.paceSeconds(distance: distance, duration: duration, unit: unit)), unit.paceSymbol)
                stat("Elevation", "\(Int(unit.elevation(fromMeters: elevationGain)))", unit.elevationSymbol)
            }
        }
        .padding(28)
        .frame(width: 360, height: 450)
        .background(background)
    }

    private func stat(_ label: String, _ value: String, _ unit: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.9)
                .foregroundStyle(muted)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 20, weight: .bold).width(.expanded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(ink)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                        .fixedSize()
                        .foregroundStyle(muted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Renders the card at 3× (1080 × 1350 px).
    @MainActor
    func uiImage() -> UIImage? {
        let renderer = ImageRenderer(content: self)
        renderer.scale = 3
        return renderer.uiImage
    }

    @MainActor
    func image() -> Image? {
        uiImage().map { Image(uiImage: $0) }
    }
}

#Preview("Ultra, 12 h") {
    ShareCardView(title: "Mountain Ultra", date: .now, distance: 100_000, duration: 45_296, elevationGain: 4_210,
                  coordinates: [], unit: .metric)
}

#Preview("Slow 5K in miles") {
    ShareCardView(title: "Recovery Jog", date: .now, distance: 5_000, duration: 3_150, elevationGain: 12,
                  coordinates: [], unit: .imperial)
}

#Preview {
    ShareCardView(title: "Long Run", date: .now, distance: 17_970, duration: 6_632, elevationGain: 157,
                  coordinates: (0..<60).map { i in
                      Coordinate(latitude: sin(Double(i) / 9.5) * 0.004, longitude: cos(Double(i) / 9.5) * 0.006)
                  }, unit: .metric)
}
