import Foundation

/// Live state of a Watch workout, sent every couple of seconds to the mirrored session on iPhone.
/// Kept small: HealthKit allows 100 KB per 10 s, so the route travels as new coordinates only.
public struct MirrorSnapshot: Codable, Sendable {
    public var sentAt: Date
    /// Moving time at `sentAt`.
    public var elapsed: TimeInterval
    public var isPaused: Bool
    /// Meters.
    public var distance: Double
    public var heartRate: Double?
    public var averageHeartRate: Double?
    /// Kilocalories.
    public var calories: Double
    /// Current speed in m/s, nil when unknown or stale.
    public var currentSpeed: Double?
    /// Seconds per heart-rate zone, keyed by zone number.
    public var zoneSeconds: [Int: TimeInterval]
    /// Route coordinates starting at `firstCoordinateIndex` of the Watch's route.
    public var coordinates: [Coordinate]
    public var firstCoordinateIndex: Int
    /// Changes when the Watch's route indices restart (after a crash recovery). iPhone keeps only
    /// the first `routeEpochBase` coordinates of the previous epoch.
    public var routeEpoch: UUID?
    public var routeEpochBase: Int
    public var goalName: String?
    /// Meters, for distance goals.
    public var goalDistance: Double?
    /// Seconds, for time goals.
    public var goalDuration: TimeInterval?

    public init(
        sentAt: Date = .now,
        elapsed: TimeInterval,
        isPaused: Bool,
        distance: Double,
        heartRate: Double? = nil,
        averageHeartRate: Double? = nil,
        calories: Double = 0,
        currentSpeed: Double? = nil,
        zoneSeconds: [Int: TimeInterval] = [:],
        coordinates: [Coordinate] = [],
        firstCoordinateIndex: Int = 0,
        routeEpoch: UUID? = nil,
        routeEpochBase: Int = 0,
        goalName: String? = nil,
        goalDistance: Double? = nil,
        goalDuration: TimeInterval? = nil
    ) {
        self.sentAt = sentAt
        self.elapsed = elapsed
        self.isPaused = isPaused
        self.distance = distance
        self.heartRate = heartRate
        self.averageHeartRate = averageHeartRate
        self.calories = calories
        self.currentSpeed = currentSpeed
        self.zoneSeconds = zoneSeconds
        self.coordinates = coordinates
        self.firstCoordinateIndex = firstCoordinateIndex
        self.routeEpoch = routeEpoch
        self.routeEpochBase = routeEpochBase
        self.goalName = goalName
        self.goalDistance = goalDistance
        self.goalDuration = goalDuration
    }

    /// Moving time now, extrapolated from the snapshot while running.
    public func elapsed(at date: Date) -> TimeInterval {
        isPaused ? elapsed : elapsed + max(date.timeIntervalSince(sentAt), 0)
    }

    public var zones: [HeartRateZone: TimeInterval] {
        Dictionary(uniqueKeysWithValues: zoneSeconds.compactMap { key, value in
            HeartRateZone(rawValue: key).map { ($0, value) }
        })
    }
}

/// Appends mirrored coordinates in order, ignoring repeats and filling nothing across gaps.
public struct MirroredRoute: Sendable {
    public private(set) var coordinates: [Coordinate] = []

    public init() {}

    /// Returns false when the batch starts after a gap, so the sender can resend from `coordinates.count`.
    @discardableResult
    public mutating func merge(_ batch: [Coordinate], startingAt index: Int) -> Bool {
        guard index <= coordinates.count else { return false }
        let overlap = coordinates.count - index
        guard overlap < batch.count else { return true }
        coordinates.append(contentsOf: batch.dropFirst(overlap))
        return true
    }

    /// Keeps only the first `count` coordinates.
    public mutating func truncate(to count: Int) {
        if count < coordinates.count { coordinates.removeSubrange(max(count, 0)...) }
    }
}

/// A run target chosen on iPhone for a run started with "Start on Watch".
public struct MirrorGoal: Codable, Hashable, Sendable {
    public var type: RunType
    /// Meters, for distance runs.
    public var distance: Double?
    /// Seconds, for time runs.
    public var duration: TimeInterval?
    public var name: String?

    public init(type: RunType, distance: Double? = nil, duration: TimeInterval? = nil, name: String? = nil) {
        self.type = type
        self.distance = distance
        self.duration = duration
        self.name = name
    }
}

/// Sent from iPhone to the Watch over the mirrored session: apply this goal to the run it just started.
public struct MirrorCommand: Codable, Sendable {
    public var goal: MirrorGoal

    public init(goal: MirrorGoal) {
        self.goal = goal
    }
}

/// Sent from iPhone back to the Watch: resend route coordinates from `resendFrom`
/// (after iPhone reconnected mid-run and missed some).
public struct MirrorRequest: Codable, Sendable {
    public var resendFrom: Int

    public init(resendFrom: Int) {
        self.resendFrom = resendFrom
    }
}
