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
            ForEach(stretches) { stretch in
                MapPolyline(coordinates: stretch.coordinates)
                    .stroke(Color.track, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
            }
            if followsUser {
                UserAnnotation()
            } else if let last = stretches.last?.coordinates.last {
                Annotation("Runner", coordinate: last) {
                    Circle()
                        .fill(Color.track)
                        .frame(width: 16, height: 16)
                        .overlay(Circle().stroke(.white, lineWidth: 3))
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
