import SwiftUI
import StrideKit
import StrideUI

/// A run in a list: the route in a small square, the title with where it was recorded, the date,
/// then distance, time and pace. Activities, Home's latest run, and the shoe and challenge screens.
/// Content only: the container pads it and draws the card.
struct RunRow: View {
    let run: Run
    let unit: UnitSystem
    /// A trailing chevron, where the row opens the run and nothing else draws one.
    var showsChevron = false
    /// A dot where the route starts, as on Home's latest run.
    var marksStart = false

    var body: some View {
        HStack(spacing: Space.x3) {
            RouteThumbnail(run: run, marksStart: marksStart)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(run.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                    if run.isManual {
                        SoftBadge("Manual", tone: .muted)
                    } else if run.source == .watch {
                        Image(systemName: "applewatch")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.inkMuted)
                    }
                }
                Text(run.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.inkMuted)
                    .lineLimit(1)
                HStack(spacing: Space.x3) {
                    Text("\(RunFormat.distance(run.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)")
                        .fontWeight(.semibold)
                        .foregroundStyle(.ink)
                    Text(RunFormat.duration(run.duration))
                    Text("\(RunFormat.pace(run.averagePace(in: unit))) \(unit.paceSymbol)")
                }
                .font(.subheadline)
                .monospacedDigit()
                .foregroundStyle(.inkMuted)
                .lineLimit(1)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                DisclosureChevron()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenSummary)
    }

    /// "Morning Run, recorded on Apple Watch, Thursday 24 September at 06:40, 5 kilometers,
    /// 28 minutes 44 seconds, 5 minutes 45 seconds per kilometer."
    private var spokenSummary: String {
        var parts = [run.title]
        if run.isManual {
            parts.append("added by hand")
        } else if run.source == .watch {
            parts.append("recorded on Apple Watch")
        }
        parts.append(run.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))
        parts.append(CoachScript.spokenDistance(run.distance, unit: unit))
        parts.append(CoachScript.spokenDuration(run.duration))
        if let pace = run.averagePace(in: unit) {
            parts.append(CoachScript.spokenPace(pace, unit: unit))
        }
        return parts.joined(separator: ", ")
    }
}

/// The route drawn as a line in a small sunken square, or an icon for runs without GPS.
struct RouteThumbnail: View {
    let run: Run
    var size: CGFloat = 56
    /// A `success` dot where the route starts.
    var marksStart = false

    var body: some View {
        let coordinates = run.preview
        ZStack {
            RoundedRectangle(cornerRadius: Radius.sm).fill(Color.surfaceSunken)
            if coordinates.count > 1 {
                GeometryReader { geo in
                    RouteShape(coordinates: coordinates)
                        .stroke(Color.track, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    if marksStart, let start = RouteShape.points(coordinates, in: CGRect(origin: .zero, size: geo.size)).first {
                        Circle()
                            .fill(Color.success)
                            .frame(width: 5, height: 5)
                            .position(start)
                    }
                }
                .padding(Space.x2)
            } else {
                Image(systemName: run.isManual ? "square.and.pencil" : "figure.run")
                    .font(.system(size: 20, weight: .medium))
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
        let points = Self.points(coordinates, in: rect)
        guard points.count > 1 else { return Path() }
        var path = Path()
        path.addLines(points)
        return path
    }

    /// The route fitted into `rect` with its aspect ratio kept, north up. Also used to place the
    /// start and finish marks on share images.
    static func points(_ coordinates: [Coordinate], in rect: CGRect) -> [CGPoint] {
        guard coordinates.count > 1 else { return [] }
        let midLatitude = coordinates.map(\.latitude).reduce(0, +) / Double(coordinates.count)
        let lonScale = cos(midLatitude * .pi / 180)
        let xs = coordinates.map { $0.longitude * lonScale }
        let ys = coordinates.map(\.latitude)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return [] }
        let width = max(maxX - minX, 1e-9), height = max(maxY - minY, 1e-9)
        let scale = min(rect.width / width, rect.height / height)
        let originX = rect.midX - width * scale / 2
        let originY = rect.midY - height * scale / 2
        return coordinates.indices.map { index in
            CGPoint(x: originX + (xs[index] - minX) * scale, y: originY + (maxY - ys[index]) * scale)
        }
    }
}
