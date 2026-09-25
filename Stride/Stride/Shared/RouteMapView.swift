import SwiftUI
import MapKit
import StrideKit
import StrideUI

/// A finished route, colored by pace: `zone-2` blue where faster than average, `zone-5` where slower,
/// drawn over a `surface` casing so it reads on any map.
struct RouteMapView: View {
    let points: [RoutePoint]
    var interactive = true

    private let segments: [RouteAnalysis.PaceSegment]

    init(points: [RoutePoint], interactive: Bool = true) {
        self.points = points
        self.interactive = interactive
        self.segments = RouteAnalysis.paceSegments(of: points)
    }

    var body: some View {
        Map(initialPosition: cameraPosition, interactionModes: interactive ? .all : []) {
            // A casing under the colored line keeps it readable on green parks and dark maps.
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(Color.surface, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
            }
            ForEach(segments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(Self.color(forSpeedRatio: segment.speedRatio),
                            style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let first = points.first {
                Annotation("Start", coordinate: first.coordinate) { marker(.success) }
                    .annotationTitles(.hidden)
            }
            if let last = points.last {
                Annotation("Finish", coordinate: last.coordinate) { marker(.ink) }
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

    private func marker(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(.white, lineWidth: 3))
    }

    static func color(forSpeedRatio ratio: Double) -> Color {
        switch ratio {
        case 1.05...: HeartRateZone.easy.color
        case 0.98..<1.05: HeartRateZone.aerobic.color
        case 0.92..<0.98: HeartRateZone.threshold.color
        default: HeartRateZone.maximum.color
        }
    }
}
