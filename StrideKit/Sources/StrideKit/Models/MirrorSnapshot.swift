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
    /// Where an interval workout is, so iPhone shows the same step as the Watch.
    public var workoutProgress: MirrorWorkoutProgress?

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
        goalDuration: TimeInterval? = nil,
        workoutProgress: MirrorWorkoutProgress? = nil
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
        self.workoutProgress = workoutProgress
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

/// An interval workout's position on the Watch, carried by each snapshot. The whole workout travels
/// along (a couple of KB) because a run started on the Watch is one iPhone has never seen.
public struct MirrorWorkoutProgress: Codable, Hashable, Sendable {
    public var workout: Workout
    /// The current step; `workout.steps.count` once every step is done.
    public var stepIndex: Int
    /// Left in the current step when the snapshot was sent.
    public var remaining: WorkoutStep.Goal?

    public init(workout: Workout, stepIndex: Int, remaining: WorkoutStep.Goal?) {
        self.workout = workout
        self.stepIndex = stepIndex
        self.remaining = remaining
    }

    public var isFinished: Bool { stepIndex >= workout.steps.count }

    public var currentStep: WorkoutStep? {
        workout.steps.indices.contains(stepIndex) ? workout.steps[stepIndex] : nil
    }

    public var nextStep: WorkoutStep? {
        workout.steps.indices.contains(stepIndex + 1) ? workout.steps[stepIndex + 1] : nil
    }

    /// Left in the current step `seconds` of moving time after the snapshot: a time step keeps
    /// counting down between snapshots, a distance step waits for the next one.
    public func remaining(after seconds: TimeInterval) -> WorkoutStep.Goal? {
        guard case .time(let left)? = remaining else { return remaining }
        return .time(max(left - max(seconds, 0), 0))
    }

    /// 0…1 through the current step, for a value from ``remaining(after:)``.
    public func progress(remaining: WorkoutStep.Goal?) -> Double {
        guard let step = currentStep else { return 1 }
        let amounts: (total: Double, left: Double)
        switch (step.goal, remaining) {
        case (.time(let total), .time(let left)?): amounts = (total, left)
        case (.distance(let total), .distance(let left)?): amounts = (total, left)
        default: return 0
        }
        return amounts.total > 0 ? min(max(1 - amounts.left / amounts.total, 0), 1) : 1
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
    /// The steps to follow, for interval runs. Optional, so goals from older app versions still decode.
    public var workout: Workout?

    public init(type: RunType, distance: Double? = nil, duration: TimeInterval? = nil, name: String? = nil,
                workout: Workout? = nil) {
        self.type = type
        self.distance = distance
        self.duration = duration
        self.name = name
        self.workout = workout
    }
}

/// What iPhone keeps on the Watch through the application context, beside units and max heart rate.
public enum WatchContext {
    /// Bool: this Apple Account has Stride Pro on iPhone. The Watch sells nothing; it only unlocks.
    public static let proActive = "proActive"
    /// Data: the workouts the Watch can start by itself, as JSON from ``encode(_:)``.
    public static let workouts = "workouts"

    public static func encode(_ workouts: [Workout]) -> Data? {
        try? JSONEncoder().encode(workouts)
    }

    /// Nil for anything that isn't a list of workouts, so a bad payload never replaces a good one.
    public static func decodeWorkouts(_ data: Data) -> [Workout]? {
        try? JSONDecoder().decode([Workout].self, from: data)
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
