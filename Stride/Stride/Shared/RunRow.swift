import SwiftUI
import StrideKit
import StrideUI

struct RunRow: View {
    let run: Run
    let unit: UnitSystem

    var body: some View {
        HStack(spacing: Space.x3) {
            RouteThumbnail(run: run)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.x1) {
                    Text(run.title)
                        .font(.headline)
                        .foregroundStyle(.ink)
                    if run.source == .watch {
                        Image(systemName: "applewatch")
                            .font(.caption)
                            .foregroundStyle(.inkMuted)
                            .accessibilityLabel("Recorded on Apple Watch")
                    }
                }
                Text(run.startDate.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                HStack(spacing: Space.x3) {
                    Text("\(RunFormat.distance(run.distance, unit: unit)) \(unit.distanceSymbol)")
                        .fontWeight(.semibold)
                    Text(RunFormat.duration(run.duration))
                    Text("\(RunFormat.pace(run.averagePace(in: unit))) \(unit.paceSymbol)")
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.ink)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.x1)
    }
}

/// The route drawn as a line in a small square, or an icon for runs without GPS.
struct RouteThumbnail: View {
    let run: Run
    var size: CGFloat = 56

    var body: some View {
        let coordinates = run.preview
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm).fill(Color.surfaceSunken)
            if coordinates.count > 1 {
                RouteShape(coordinates: coordinates)
                    .stroke(Color.track, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .padding(Space.x2)
            } else {
                Image(systemName: run.isManual ? "square.and.pencil" : "figure.run")
                    .foregroundStyle(.inkMuted)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Fits a list of coordinates into a rect, keeping the route's proportions.
/// Nonisolated because `Shape` requires `path(in:)` to be callable off the main actor.
nonisolated struct RouteShape: Shape {
    let coordinates: [Coordinate]

    func path(in rect: CGRect) -> Path {
        guard coordinates.count > 1 else { return Path() }
        let midLatitude = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
        let lonScale = cos(midLatitude * .pi / 180)
        let xs = coordinates.map { $0.longitude * lonScale }
        let ys = coordinates.map(\.latitude)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return Path() }
        let width = max(maxX - minX, 1e-9), height = max(maxY - minY, 1e-9)
        let scale = min(rect.width / width, rect.height / height)
        let originX = rect.midX - width * scale / 2
        let originY = rect.midY - height * scale / 2

        var path = Path()
        for index in coordinates.indices {
            let point = CGPoint(x: originX + (xs[index] - minX) * scale,
                                y: originY + (maxY - ys[index]) * scale)
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        return path
    }
}
