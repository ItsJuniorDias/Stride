import SwiftUI
import MapKit
import StrideKit
import StrideUI

/// The route so far, following the runner. One polyline per stretch so paused gaps aren't joined.
struct LiveRouteMap: View {
    private let stretches: [Stretch]
    /// Follow the phone's own location (iPhone runs) or the route's last point (Apple Watch runs).
    private let followsUser: Bool
    @State private var position: MapCameraPosition

    private struct Stretch: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
    }

    /// A route recorded on this iPhone.
    init(route: [RoutePoint]) {
        let step = max(route.count / 1_500, 1)
        let thinned = stride(from: 0, to: route.count, by: step).map { route[$0] } + (route.last.map { [$0] } ?? [])
        stretches = Dictionary(grouping: thinned, by: \.segment)
            .sorted { $0.key < $1.key }
            .map { Stretch(id: $0.key, coordinates: $0.value.map(\.coordinate)) }
        followsUser = true
        _position = State(initialValue: .userLocation(followsHeading: false, fallback: .automatic))
    }

    /// A route mirrored from Apple Watch.
    init(coordinates: [Coordinate]) {
        let step = max(coordinates.count / 1_500, 1)
        let thinned = stride(from: 0, to: coordinates.count, by: step).map { coordinates[$0] } + (coordinates.last.map { [$0] } ?? [])
        stretches = [Stretch(id: 0, coordinates: thinned.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })]
        followsUser = false
        _position = State(initialValue: .automatic)
    }

    var body: some View {
        Map(position: $position) {
            // A dark casing under the brand line keeps the route readable on any map tile.
            ForEach(stretches) { stretch in
                MapPolyline(coordinates: stretch.coordinates)
                    .stroke(Color.surface, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: stretch.coordinates)
                    .stroke(Color.track, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }
            if let start = stretches.first?.coordinates.first {
                Annotation("Start", coordinate: start) {
                    Circle()
                        .fill(Color.success)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color.surface, lineWidth: 2))
                }
                .annotationTitles(.hidden)
            }
            if followsUser {
                UserAnnotation()
            } else if let last = stretches.last?.coordinates.last {
                Annotation("Runner", coordinate: last) {
                    // White ring on purpose (not ink), so it stays light in light mode too.
                    ZStack {
                        Circle().fill(Color.lane.opacity(0.18)).frame(width: 36, height: 36)
                        Circle().fill(Color.white).frame(width: 17, height: 17)
                        Circle().fill(Color.lane).frame(width: 12, height: 12)
                    }
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            if followsUser { MapUserLocationButton() }
        }
    }
}
