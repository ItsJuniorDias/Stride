import CoreLocation

/// Pure functions over a recorded route. Points in different segments (split by pauses)
/// are never joined, so paused time and the distance walked while paused don't count.
public enum RouteAnalysis {
    /// Meters covered, summed within segments.
    public static func distance(of points: [RoutePoint]) -> Double {
        pairs(points).reduce(0) { $0 + $1.0.location.distance(from: $1.1.location) }
    }

    /// Seconds between consecutive points within segments.
    public static func movingTime(of points: [RoutePoint]) -> TimeInterval {
        pairs(points).reduce(0) { $0 + max($1.1.timestamp.timeIntervalSince($1.0.timestamp), 0) }
    }

    /// Elevation gain and loss with a hysteresis threshold, so GPS altitude noise doesn't add up.
    /// Altitude changed during a pause (between segments) is not counted.
    public static func elevation(of points: [RoutePoint], threshold: Double = 3) -> (gain: Double, loss: Double) {
        guard let first = points.first else { return (0, 0) }
        var reference = first.altitude
        var segment = first.segment
        var gain = 0.0, loss = 0.0
        for point in points.dropFirst() {
            if point.segment != segment {
                segment = point.segment
                reference = point.altitude
                continue
            }
            let delta = point.altitude - reference
            if delta >= threshold {
                gain += delta
                reference = point.altitude
            } else if delta <= -threshold {
                loss -= delta
                reference = point.altitude
            }
        }
        return (gain, loss)
    }

    /// Splits per unit, interpolating the exact moment each boundary was crossed.
    /// A final partial split is included when it is at least 50 m.
    /// `scale` stretches GPS distance to match a more accurate total, e.g. Apple Watch's workout distance.
    public static func splits(from points: [RoutePoint], unit: UnitSystem, scale: Double = 1) -> [Split] {
        guard points.count > 1 else { return [] }
        let length = unit.metersPerUnit
        var splits: [Split] = []
        var covered = 0.0, elapsed = 0.0
        var splitStartTime = 0.0, splitStartAltitude = points[0].altitude
        var boundary = length

        for (a, b) in pairs(points) {
            let d = a.location.distance(from: b.location) * scale
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard d > 0, dt > 0 else { continue }
            while covered + d >= boundary {
                let fraction = (boundary - covered) / d
                let time = elapsed + dt * fraction
                let altitude = a.altitude + (b.altitude - a.altitude) * fraction
                splits.append(Split(index: splits.count + 1, distance: length,
                                    duration: time - splitStartTime,
                                    elevationDelta: altitude - splitStartAltitude))
                splitStartTime = time
                splitStartAltitude = altitude
                boundary += length
            }
            covered += d
            elapsed += dt
        }

        let remainder = covered - (boundary - length)
        if remainder >= 50, let last = points.last {
            splits.append(Split(index: splits.count + 1, distance: remainder,
                                duration: elapsed - splitStartTime,
                                elevationDelta: last.altitude - splitStartAltitude))
        }
        return splits
    }

    /// Seconds spent in each heart-rate zone, from the heart rate stored on route points.
    /// Each interval between two points in the same segment counts toward the earlier point's zone.
    public static func zoneSeconds(of points: [RoutePoint], maxHeartRate: Double) -> [HeartRateZone: TimeInterval] {
        var result: [HeartRateZone: TimeInterval] = [:]
        for (a, b) in pairs(points) {
            guard let bpm = a.heartRate, let zone = HeartRateZone.zone(for: bpm, maxHeartRate: maxHeartRate) else { continue }
            result[zone, default: 0] += max(b.timestamp.timeIntervalSince(a.timestamp), 0)
        }
        return result
    }

    /// A value at a distance along the route, for charts.
    public struct SeriesPoint: Identifiable, Hashable, Sendable {
        /// Meters from the start.
        public let distance: Double
        public let value: Double
        public var id: Double { distance }

        public init(distance: Double, value: Double) {
            self.distance = distance
            self.value = value
        }
    }

    /// Pace (seconds per unit) every `bucket` meters, smoothed over three buckets.
    /// Buckets never span a pause, and standing still (under 0.5 m/s, e.g. at a light without
    /// pausing) is left out, so a stop doesn't show as one very slow stretch.
    public static func paceSeries(of points: [RoutePoint], unit: UnitSystem, bucket: Double = 100, scale: Double = 1) -> [SeriesPoint] {
        var raw: [SeriesPoint] = []
        var covered = 0.0, bucketDistance = 0.0, bucketTime = 0.0
        for (a, b) in pairs(points) {
            let d = a.location.distance(from: b.location) * scale
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard d > 0, dt > 0, d / dt >= 0.5 else { continue }
            covered += d
            bucketDistance += d
            bucketTime += dt
            if bucketDistance >= bucket {
                raw.append(SeriesPoint(distance: covered, value: bucketTime / (bucketDistance / unit.metersPerUnit)))
                bucketDistance = 0
                bucketTime = 0
            }
        }
        return smoothed(raw, window: 3)
    }

    /// Altitude every `bucket` meters.
    public static func elevationSeries(of points: [RoutePoint], bucket: Double = 50, scale: Double = 1) -> [SeriesPoint] {
        guard let first = points.first else { return [] }
        var result = [SeriesPoint(distance: 0, value: first.altitude)]
        var covered = 0.0, next = bucket
        for (a, b) in pairs(points) {
            covered += a.location.distance(from: b.location) * scale
            if covered >= next {
                result.append(SeriesPoint(distance: covered, value: b.altitude))
                next = covered + bucket
            }
        }
        return result
    }

    /// Average heart rate every `bucket` meters where the route carries heart rate, smoothed over five buckets.
    public static func heartRateSeries(of points: [RoutePoint], bucket: Double = 100, scale: Double = 1) -> [SeriesPoint] {
        var result: [SeriesPoint] = []
        var covered = 0.0, bucketDistance = 0.0
        var rates: [Double] = []
        for (a, b) in pairs(points) {
            let d = a.location.distance(from: b.location) * scale
            covered += d
            bucketDistance += d
            if let bpm = b.heartRate { rates.append(bpm) }
            if bucketDistance >= bucket {
                if !rates.isEmpty {
                    result.append(SeriesPoint(distance: covered, value: rates.reduce(0, +) / Double(rates.count)))
                }
                bucketDistance = 0
                rates = []
            }
        }
        return smoothed(result, window: 5)
    }

    private static func smoothed(_ series: [SeriesPoint], window: Int) -> [SeriesPoint] {
        guard series.count > window else { return series }
        let half = window / 2
        return series.indices.map { index in
            let range = max(index - half, 0)...min(index + half, series.count - 1)
            let average = series[range].reduce(0) { $0 + $1.value } / Double(range.count)
            return SeriesPoint(distance: series[index].distance, value: average)
        }
    }

    /// Everything the run detail screen draws from the route, computed off the main actor.
    public struct ChartData: Sendable {
        public var route: [RoutePoint]
        /// Recomputed splits for miles; nil for kilometers, which use the stored splits.
        public var imperialSplits: [Split]?
        public var pace: [SeriesPoint]
        public var elevation: [SeriesPoint]
        public var heartRate: [SeriesPoint]
    }

    /// Decodes the route (unless it's already decoded) and builds the chart series and mile splits.
    @concurrent
    public static func chartData(routeData: Data?, decodedRoute: [RoutePoint], heartRates: [Double?] = [],
                                 distance: Double, duration: TimeInterval,
                                 source: RunSource, unit: UnitSystem) async -> ChartData {
        let decoded = decodedRoute.isEmpty
            ? (routeData.flatMap { try? JSONDecoder().decode([RoutePoint].self, from: $0) } ?? [])
            : decodedRoute
        // Heart rate is kept apart from the synced route (see RunVitals).
        let route = heartRates.isEmpty ? decoded : RunVitals.merge(decoded, heartRates: heartRates)
        let chartScale = Run.chartScale(distance: distance, duration: duration, route: route, source: source)
        let splitScale = Run.splitScale(distance: distance, route: route, source: source)
        return ChartData(
            route: route,
            imperialSplits: unit == .imperial ? splits(from: route, unit: unit, scale: splitScale) : nil,
            pace: paceSeries(of: route, unit: unit, scale: chartScale),
            elevation: elevationSeries(of: route, scale: chartScale),
            heartRate: heartRateSeries(of: route, scale: chartScale)
        )
    }

    /// At most `maxPoints` coordinates, evenly sampled, for thumbnails.
    public static func preview(of points: [RoutePoint], maxPoints: Int = 80) -> [Coordinate] {
        guard !points.isEmpty else { return [] }
        let step = max(points.count / maxPoints, 1)
        var result = stride(from: 0, to: points.count, by: step).map {
            Coordinate(latitude: points[$0].latitude, longitude: points[$0].longitude)
        }
        if let last = points.last, step > 1 {
            result.append(Coordinate(latitude: last.latitude, longitude: last.longitude))
        }
        return result
    }

    /// A stretch of the route with its speed relative to the run's average, for pace-colored maps.
    public struct PaceSegment: Identifiable {
        public let id: Int
        public let coordinates: [CLLocationCoordinate2D]
        /// Segment speed ÷ average speed: above 1 is faster than average.
        public let speedRatio: Double
    }

    public static func paceSegments(of points: [RoutePoint], pointsPerSegment: Int = 8) -> [PaceSegment] {
        let average = distance(of: points) / max(movingTime(of: points), 1)
        guard points.count > 1, average > 0 else { return [] }
        var segments: [PaceSegment] = []
        var chunk: [RoutePoint] = []

        func flush() {
            guard chunk.count > 1 else { return }
            let speed = distance(of: chunk) / max(movingTime(of: chunk), 1)
            segments.append(PaceSegment(id: segments.count, coordinates: chunk.map(\.coordinate), speedRatio: speed / average))
        }

        for point in points {
            if let last = chunk.last, last.segment != point.segment {
                flush()
                chunk = []
            }
            chunk.append(point)
            if chunk.count > pointsPerSegment {
                flush()
                chunk = [point]
            }
        }
        flush()
        return segments
    }

    private static func pairs(_ points: [RoutePoint]) -> [(RoutePoint, RoutePoint)] {
        zip(points, points.dropFirst()).filter { $0.0.segment == $0.1.segment }
    }
}
