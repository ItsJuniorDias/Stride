import SwiftUI
import MapKit
import CoreLocation
import StrideKit
import StrideUI

/// A finished route colored by pace (``PaceScale``: blue where faster than the run's average, orange
/// where slower), drawn over a `surface` casing so it reads on any map. A green start dot, an ink
/// finish dot, and optionally a numbered marker at every kilometer or mile.
struct RouteMapView: View {
    let points: [RoutePoint]
    var interactive = true

    private let segments: [RouteAnalysis.PaceSegment]
    private let markers: [SplitMarker]

    /// - Parameter splitMarkers: the unit to number the route in (1, 2, 3… at each kilometer or
    ///   mile), or nil for none.
    init(points: [RoutePoint], interactive: Bool = true, splitMarkers: UnitSystem? = nil) {
        self.points = points
        self.interactive = interactive
        self.segments = RouteAnalysis.paceSegments(of: points)
        self.markers = splitMarkers.map { Self.splitMarkers(along: points, unit: $0) } ?? []
    }

    var body: some View {
        Map(initialPosition: cameraPosition, interactionModes: interactive ? .all : []) {
            // A casing under the colored line keeps it readable on green parks and dark maps.
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(Color.surface, style: StrokeStyle(lineWidth: 10, lineCap: .round, lineJoin: .round))
            }
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(PaceScale.color(forSpeedRatio: segment.speedRatio),
                            style: StrokeStyle(lineWidth: 5.5, lineCap: .round, lineJoin: .round))
            }
            ForEach(markers) { marker in
                Annotation(marker.title, coordinate: marker.coordinate) {
                    Text(verbatim: "\(marker.number)")
                        .font(.system(size: 10, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.ink)
                        .frame(width: 17, height: 17)
                        .background(Color.surface, in: Circle())
                        .overlay(Circle().stroke(Color.ink, lineWidth: 1.5))
                }
                .annotationTitles(.hidden)
            }
            if let last = points.last {
                Annotation("Finish", coordinate: last.coordinate) {
                    Circle()
                        .fill(Color.ink)
                        .frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.surface, lineWidth: 2.5))
                }
                .annotationTitles(.hidden)
            }
            // Last, so the start sits on top where a loop ends where it began.
            if let first = points.first {
                Annotation("Start", coordinate: first.coordinate) {
                    Circle()
                        .fill(Color.success)
                        .frame(width: 13, height: 13)
                        .overlay(Circle().stroke(Color.ink, lineWidth: 2.5))
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
    }

    private var cameraPosition: MapCameraPosition {
        guard !points.isEmpty else { return .automatic }
        let mapPoints = points.map { MKMapPoint($0.coordinate) }
        let minX = mapPoints.map(\.x).min()!, maxX = mapPoints.map(\.x).max()!
        let minY = mapPoints.map(\.y).min()!, maxY = mapPoints.map(\.y).max()!
        let rect = MKMapRect(x: minX, y: minY, width: max(maxX - minX, 500), height: max(maxY - minY, 500))
        return .rect(rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.25))
    }

    /// The pace colors, kept here for callers that color by speed ratio.
    static func color(forSpeedRatio ratio: Double) -> Color {
        PaceScale.color(forSpeedRatio: ratio)
    }

    // MARK: - Split markers

    private struct SplitMarker: Identifiable {
        let number: Int
        let coordinate: CLLocationCoordinate2D
        let title: String
        var id: Int { number }
    }

    /// Where the route passes each whole unit, interpolated between fixes; distance only adds up
    /// within segments, as for splits. Long runs number every 2, 5 or 10 units so markers don't crowd.
    private static func splitMarkers(along points: [RoutePoint], unit: UnitSystem) -> [SplitMarker] {
        guard points.count > 1 else { return [] }
        let total = RouteAnalysis.distance(of: points) / unit.metersPerUnit
        let every: Int = switch total {
        case ..<16: 1
        case ..<31: 2
        case ..<61: 5
        default: 10
        }
        let step = Double(every) * unit.metersPerUnit
        let name = unit == .metric ? "Kilometer" : "Mile"
        var markers: [SplitMarker] = []
        var covered = 0.0
        var next = step
        for (a, b) in zip(points, points.dropFirst()) where a.segment == b.segment {
            let d = a.location.distance(from: b.location)
            guard d > 0 else { continue }
            while covered + d >= next {
                let fraction = (next - covered) / d
                let coordinate = CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * fraction,
                                                        longitude: a.longitude + (b.longitude - a.longitude) * fraction)
                let number = (markers.count + 1) * every
                markers.append(SplitMarker(number: number, coordinate: coordinate, title: "\(name) \(number)"))
                next += step
            }
            covered += d
        }
        return markers
    }
}
