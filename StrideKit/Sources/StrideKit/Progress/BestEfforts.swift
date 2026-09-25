import Foundation
import CoreLocation

/// The standard distances Stride keeps best times for.
public enum EffortDistance: Int, CaseIterable, Codable, Identifiable, Sendable {
    case oneK = 1_000
    case oneMile = 1_609
    case fiveK = 5_000
    case tenK = 10_000
    case half = 21_098
    case marathon = 42_195

    public var id: Int { rawValue }

    public var meters: Double {
        switch self {
        case .oneMile: 1_609.344
        case .half: 21_097.5
        default: Double(rawValue)
        }
    }

    public var title: String {
        switch self {
        case .oneK: "1K"
        case .oneMile: "1 mile"
        case .fiveK: "5K"
        case .tenK: "10K"
        case .half: "half marathon"
        case .marathon: "marathon"
        }
    }
}

/// Fastest times over standard distances within one run.
public enum BestEfforts {
    /// Bump when the algorithm changes, so runs saved with an older one are recomputed.
    public static let version = 4

    /// A GPS run that reads as the full distance counts for it: stopping at "5.00 km" or "3.11 mi" can
    /// fall a few meters short. Half of 0.01 mi, the coarser of the two displays.
    static let shortfall: Double = 0.005 * 1_609.344

    /// A distance typed by hand counts within 0.25%: 3.1 mi, 6.2 mi, 13.1 mi and 26.2 mi are the
    /// usual way to write a 5K, 10K, half and marathon.
    static func typedShortfall(_ effort: EffortDistance) -> Double {
        max(shortfall, effort.meters * 0.002_5)
    }

    /// Anything faster than about the world record over the distance isn't a running effort: GPS
    /// jumps, a car or a bike.
    static func fastestPlausible(_ effort: EffortDistance) -> TimeInterval {
        switch effort {
        case .oneK: 130
        case .oneMile: 220
        case .fiveK: 750
        case .tenK: 1_560
        case .half: 3_440
        case .marathon: 7_200
        }
    }

    /// Best efforts from the route, fitted to the run's own distance and time, or estimated from the
    /// average pace when there's no route. Distances the route doesn't reach but the run does (GPS
    /// locked late, or dropped out) come from the average pace too. `typed` is for a distance entered
    /// by hand, which gets the looser tolerance of round numbers.
    public static func compute(route: [RoutePoint], distance: Double, duration: TimeInterval,
                               typed: Bool = false) -> [EffortDistance: TimeInterval] {
        let routeDistance = RouteAnalysis.distance(of: route)
        let routeTime = RouteAnalysis.movingTime(of: route)
        guard route.count > 1, routeDistance > 0, routeTime > 0 else {
            return estimated(distance: distance, duration: duration, typed: typed)
        }
        // A route shorter than the run (Apple Watch's distance is measured apart from GPS) is stretched
        // to it, but only as far as the speeds agree: a route that started late is short in distance
        // and time alike, and stretching it by distance alone would make every stretch faster than it
        // was run. A route is never shrunk for speed: on iPhone the clock always runs a little longer
        // than the route (waiting for the first fix, the last seconds before Stop).
        var scale = 1.0
        if distance > 0, duration > 0 {
            let byDistance = distance / routeDistance
            let bySpeed = (distance / duration) / (routeDistance / routeTime)
            scale = min(max(byDistance > 1 ? min(byDistance, max(bySpeed, 1)) : byDistance, 0.5), 2)
        }
        return fromRoute(route, scale: scale)
            .merging(estimated(distance: distance, duration: duration, typed: false)) { fromRoute, _ in fromRoute }
    }

    /// ``compute(route:distance:duration:)`` for a stored route, decoded off the main actor.
    @concurrent
    public static func compute(routeData: Data?, distance: Double, duration: TimeInterval,
                               typed: Bool = false) async -> [EffortDistance: TimeInterval] {
        let route = routeData.flatMap { try? JSONDecoder().decode([RoutePoint].self, from: $0) } ?? []
        return compute(route: route, distance: distance, duration: duration, typed: typed)
    }

    /// The fastest stretch of each standard distance anywhere in the route: a sliding window over
    /// cumulative distance and time, with the window's start interpolated to the exact meter.
    /// Distance and time only add up within segments, so pauses never count.
    public static func fromRoute(_ points: [RoutePoint], scale: Double = 1) -> [EffortDistance: TimeInterval] {
        guard points.count > 1 else { return [:] }
        var meters: [Double] = [0]
        var seconds: [Double] = [0]
        meters.reserveCapacity(points.count)
        seconds.reserveCapacity(points.count)
        for (a, b) in zip(points, points.dropFirst()) {
            let sameSegment = a.segment == b.segment
            let d = sameSegment ? a.location.distance(from: b.location) * scale : 0
            let t = sameSegment ? max(b.timestamp.timeIntervalSince(a.timestamp), 0) : 0
            meters.append(meters[meters.count - 1] + d)
            seconds.append(seconds[seconds.count - 1] + t)
        }

        var result: [EffortDistance: TimeInterval] = [:]
        // A route stretched to exactly 5,000 m can add up to 4,999.99999 m.
        let tolerance = 0.01
        let total = meters[meters.count - 1]
        let totalSeconds = seconds[seconds.count - 1]
        for effort in EffortDistance.allCases where effort.meters <= total + shortfall {
            let target = effort.meters
            let fastest = fastestPlausible(effort)
            guard total + tolerance >= target else {
                // Just short of the distance: the whole run, at its average pace.
                let time = totalSeconds * target / total
                if total > 0, time >= fastest { result[effort] = time }
                continue
            }
            var best = Double.infinity
            var start = 0
            for end in 1..<meters.count where meters[end] + tolerance >= target {
                // Move the start up while the window stays at least `target` long.
                while start + 1 < end, meters[end] - meters[start + 1] >= target { start += 1 }
                let startMeters = max(meters[end] - target, 0)
                let span = meters[start + 1] - meters[start]
                let fraction = span > 0 ? (startMeters - meters[start]) / span : 0
                let startSeconds = seconds[start] + (seconds[start + 1] - seconds[start]) * fraction
                let time = seconds[end] - startSeconds
                if time >= fastest { best = min(best, time) }
            }
            if best.isFinite { result[effort] = best }
        }
        return result
    }

    /// The run's average pace over every standard distance it covers (or reads as covering). That can
    /// only understate the true best effort, never overstate it. `typed` allows the looser tolerance
    /// of a distance entered by hand.
    public static func estimated(distance: Double, duration: TimeInterval, typed: Bool = true) -> [EffortDistance: TimeInterval] {
        guard distance > 0, duration > 0 else { return [:] }
        var result: [EffortDistance: TimeInterval] = [:]
        for effort in EffortDistance.allCases where effort.meters <= distance + (typed ? typedShortfall(effort) : shortfall) {
            let time = duration * effort.meters / distance
            if time >= fastestPlausible(effort) { result[effort] = time }
        }
        return result
    }
}
