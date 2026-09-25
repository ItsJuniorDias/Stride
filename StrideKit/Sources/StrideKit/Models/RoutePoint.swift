import CoreLocation

/// One recorded GPS fix. `segment` increases after every pause so distance and time
/// are never counted across a gap.
public struct RoutePoint: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double
    public var altitude: Double
    public var timestamp: Date
    public var segment: Int
    public var heartRate: Double?

    public init(latitude: Double, longitude: Double, altitude: Double, timestamp: Date, segment: Int = 0, heartRate: Double? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.altitude = altitude
        self.timestamp = timestamp
        self.segment = segment
        self.heartRate = heartRate
    }

    public var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    public var location: CLLocation {
        CLLocation(coordinate: coordinate, altitude: altitude, horizontalAccuracy: 5, verticalAccuracy: 5, timestamp: timestamp)
    }
}

/// A plain latitude/longitude pair, used for small route previews.
public struct Coordinate: Codable, Hashable, Sendable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}
