import Foundation

/// A finished run as sent from Apple Watch to iPhone. Plain Codable data, so it can travel as a file.
public struct RunTransfer: Codable, Identifiable, Sendable {
    public var id: UUID
    public var startDate: Date
    /// Moving time in seconds.
    public var duration: TimeInterval
    /// Meters.
    public var distance: Double
    /// Kilocalories.
    public var calories: Double
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    /// Seconds per heart-rate zone, keyed by zone number (1…5).
    public var zoneSeconds: [Int: TimeInterval]
    public var route: [RoutePoint]
    public var type: RunType
    public var workoutName: String?

    public init(
        id: UUID = UUID(),
        startDate: Date,
        duration: TimeInterval,
        distance: Double,
        calories: Double,
        averageHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        zoneSeconds: [Int: TimeInterval] = [:],
        route: [RoutePoint] = [],
        type: RunType = .free,
        workoutName: String? = nil
    ) {
        self.id = id
        self.startDate = startDate
        self.duration = duration
        self.distance = distance
        self.calories = calories
        self.averageHeartRate = averageHeartRate
        self.maxHeartRate = maxHeartRate
        self.zoneSeconds = zoneSeconds
        self.route = route
        self.type = type
        self.workoutName = workoutName
    }

    public var zones: [HeartRateZone: TimeInterval] {
        Dictionary(uniqueKeysWithValues: zoneSeconds.compactMap { key, value in
            HeartRateZone(rawValue: key).map { ($0, value) }
        })
    }
}
