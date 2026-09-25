#if canImport(ActivityKit) && os(iOS)
import Foundation
import ActivityKit

/// The run on the Lock Screen, in the Dynamic Island and in Apple Watch's Smart Stack.
public struct RunActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public enum Status: String, Codable, Hashable, Sendable {
            case running, paused, autoPaused, finished
        }

        public var status: Status
        /// Meters.
        public var distance: Double
        /// Seconds on the run clock when this state was sent.
        public var elapsed: TimeInterval
        /// While running: when the clock would have read 0:00, so the view counts up on its own.
        public var clockStart: Date?
        /// Seconds per unit: the current pace, or the average when there's none.
        public var pace: Double?
        /// The workout step, e.g. "Run · 3 of 8".
        public var step: String?
        /// When a timed step ends, so the view counts down on its own.
        public var stepEnd: Date?
        /// Meters left in a distance step when this state was sent.
        public var stepRemaining: Double?
        /// A run picked up after the app was closed can only resume from inside the app (GPS can't
        /// start in the background): the resume button opens Stride instead.
        public var resumeInApp: Bool = false

        public init(status: Status, distance: Double, elapsed: TimeInterval, clockStart: Date?, pace: Double?,
                    step: String? = nil, stepEnd: Date? = nil, stepRemaining: Double? = nil) {
            self.status = status
            self.distance = distance
            self.elapsed = elapsed
            self.clockStart = clockStart
            self.pace = pace
            self.step = step
            self.stepEnd = stepEnd
            self.stepRemaining = stepRemaining
        }
    }

    /// "Morning Run", "8 × 400 m", "Week 2 · Run 1".
    public var title: String
    public var unit: UnitSystem

    public init(title: String, unit: UnitSystem) {
        self.title = title
        self.unit = unit
    }
}
#endif
