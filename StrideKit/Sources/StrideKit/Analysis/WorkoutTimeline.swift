import Foundation

/// When a workout started and ended, and the pauses in between, so an app that counts pauses out
/// (Apple Health) arrives at the run's moving time.
public struct WorkoutTimeline: Sendable, Equatable {
    public var start: Date
    public var end: Date
    public var pauses: [DateInterval]

    /// - Parameters:
    ///   - duration: Moving time, pauses excluded.
    ///   - route: The recorded route; a new segment starts after every pause.
    ///   - now: Nothing may end after this (a run logged by hand as starting now).
    public init(start: Date, duration: TimeInterval, route: [RoutePoint], now: Date = .now) {
        var pauses = zip(route, route.dropFirst())
            .filter { $0.0.segment != $0.1.segment && $0.1.timestamp > $0.0.timestamp }
            .map { DateInterval(start: $0.0.timestamp, end: $0.1.timestamp) }
        let paused = pauses.reduce(0) { $0 + $1.duration }
        var end = max(start.addingTimeInterval(duration + paused), route.last?.timestamp ?? start)
        // A pause the route can't show (before the first fix, e.g. auto-paused at the start line)
        // still has to come off: it goes just before the first fix.
        let missing = end.timeIntervalSince(start) - duration - paused
        if missing > 2, let first = route.first?.timestamp, first > start {
            let pauseStart = max(start, first.addingTimeInterval(-missing))
            if first.timeIntervalSince(pauseStart) > 1 {
                pauses.insert(DateInterval(start: pauseStart, end: first), at: 0)
            }
        }
        // Shifted back so nothing ends in the future.
        var start = start
        if end > now {
            let shift = end.timeIntervalSince(now)
            start = start.addingTimeInterval(-shift)
            end = now
            pauses = pauses.map { DateInterval(start: $0.start.addingTimeInterval(-shift), end: $0.end.addingTimeInterval(-shift)) }
        }
        self.start = start
        self.end = end
        self.pauses = pauses
    }

    /// Time between start and end, pauses excluded.
    public var movingTime: TimeInterval {
        end.timeIntervalSince(start) - pauses.reduce(0) { $0 + $1.duration }
    }
}
