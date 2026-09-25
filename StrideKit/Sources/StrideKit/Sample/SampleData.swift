import Foundation
import SwiftData

/// Realistic example runs around São Paulo parks, for development and screenshots.
/// Deterministic: the same seed always produces the same runs.
public enum SampleData {
    private struct Plan: Sendable {
        let daysAgo: Int
        let hour: Int
        let minute: Int
        let kilometers: Double
        /// Seconds per kilometer.
        let pace: Double
        let name: String?
        let intervals: Bool
        let feeling: Feeling?
        let surface: Surface?
        let notes: String
    }

    private static let parks = [
        Coordinate(latitude: -23.5874, longitude: -46.6576), // Ibirapuera
        Coordinate(latitude: -23.5613, longitude: -46.7307), // USP
        Coordinate(latitude: -23.5534, longitude: -46.6912), // Villa-Lobos
    ]

    /// The expensive part of a sample run (route generation and analysis), computed off the main actor.
    private struct Prepared: Sendable {
        let plan: Plan
        let start: Date
        let routeData: Data?
        let previewData: Data?
        let splitsData: Data?
        let distance: Double
        let duration: TimeInterval
        let elevationGain: Double
        let elevationLoss: Double
        let averageHeartRate: Double?
        let zoneSeconds: [HeartRateZone: TimeInterval]
        let bestEfforts: [EffortDistance: TimeInterval]
        let heartRates: [Double?]
    }

    private static func prepare(now: Date) -> [Prepared] {
        var rng = SeededRandom(seed: 2_026)
        var prepared: [Prepared] = []
        for (index, plan) in plans(now: now).enumerated() {
            guard let day = Calendar.current.date(byAdding: .day, value: -plan.daysAgo, to: now),
                  let start = Calendar.current.date(bySettingHour: plan.hour, minute: plan.minute, second: 0, of: day),
                  start < now
            else { continue }
            let points = route(start: start, meters: plan.kilometers * 1_000, pace: plan.pace,
                               center: parks[index % parks.count], intervals: plan.intervals, rng: &rng)
            let elevation = RouteAnalysis.elevation(of: points)
            let rates = points.compactMap(\.heartRate)
            let encoder = JSONEncoder()
            let distance = RouteAnalysis.distance(of: points)
            let duration = RouteAnalysis.movingTime(of: points)
            let split = RunVitals.split(points)
            prepared.append(Prepared(
                plan: plan,
                start: start,
                routeData: try? encoder.encode(split.route),
                previewData: try? encoder.encode(RouteAnalysis.preview(of: points)),
                splitsData: try? encoder.encode(RouteAnalysis.splits(from: points, unit: .metric)),
                distance: distance,
                duration: duration,
                elevationGain: elevation.gain,
                elevationLoss: elevation.loss,
                averageHeartRate: rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count),
                zoneSeconds: RouteAnalysis.zoneSeconds(of: points, maxHeartRate: HeartRateZone.defaultMaxHeartRate),
                bestEfforts: BestEfforts.compute(route: points, distance: distance, duration: duration),
                heartRates: split.heartRates
            ))
        }
        return prepared
    }

    /// Generates the routes in the background, then inserts the runs and shoes into `context`.
    @MainActor
    public static func insert(into context: ModelContext, now: Date = .now, weightKg: Double = 70) async {
        let prepared = await Task.detached(priority: .userInitiated) { prepare(now: now) }.value

        let daily = Shoe(name: "Daily Trainer", brand: "Road · neutral", initialDistance: 184_000)
        let race = Shoe(name: "Race Day", brand: "Carbon plate", initialDistance: 42_000, maxDistance: 500_000)
        race.colorIndex = 1
        let old = Shoe(name: "Old Faithful", brand: "Road · stability", initialDistance: 812_000)
        old.colorIndex = 4
        old.isRetired = true
        [daily, race, old].forEach(context.insert)

        for (index, item) in prepared.enumerated() {
            let plan = item.plan
            let run = Run(startDate: item.start, duration: item.duration, distance: item.distance,
                          calories: Run.estimatedCalories(distance: item.distance, weightKg: weightKg),
                          type: plan.intervals ? .intervals : .free)
            run.routeData = item.routeData
            run.previewData = item.previewData
            run.splitsData = item.splitsData
            run.elevationGain = item.elevationGain
            run.elevationLoss = item.elevationLoss
            let vitals = RunVitals(runID: run.id, averageHeartRate: item.averageHeartRate)
            vitals.zoneSeconds = item.zoneSeconds
            vitals.heartRates = item.heartRates
            context.insert(vitals)
            run.bestEfforts = item.bestEfforts
            run.effortsVersion = BestEfforts.version
            if index.isMultiple(of: 3) { run.source = .watch }
            run.workoutName = plan.name
            run.feeling = plan.feeling
            run.surface = plan.surface
            run.notes = plan.notes
            run.shoe = plan.name == "5K Race" ? race : daily
            context.insert(run)
        }

        let treadmill = Run(startDate: Calendar.current.date(byAdding: .day, value: -9, to: now) ?? now,
                            duration: 1_860, distance: 5_200, type: .free, isManual: true)
        treadmill.calories = Run.estimatedCalories(distance: 5_200, weightKg: weightKg)
        treadmill.workoutName = "Treadmill Run"
        treadmill.surface = .treadmill
        treadmill.feeling = .okay
        treadmill.notes = "Rainy day, gym treadmill at 1% incline."
        treadmill.shoe = daily
        treadmill.updateBestEfforts(route: [])
        context.insert(treadmill)

        // One challenge running this month, and one finished last month.
        let catalog = ChallengeTemplate.catalog(unit: .metric)
        if let monthly = catalog.first(where: { $0.id == "monthly-distance" }) {
            context.insert(monthly.makeChallenge(now: now))
        }
        if let runs = catalog.first(where: { $0.id == "monthly-runs" }),
           let lastMonth = Calendar.current.date(byAdding: .month, value: -1, to: now) {
            context.insert(runs.makeChallenge(now: lastMonth))
        }

        try? context.save()
    }

    /// Ten weeks of training: easy runs midweek, a quality session, a long run on Sunday.
    private static func plans(now: Date) -> [Plan] {
        let notes = ["", "", "Felt strong on the hills.", "", "Hot and humid, kept it easy.", "", "Negative split!", ""]
        var plans: [Plan] = []
        for week in 0..<10 where week != 5 {
            let base = week * 7
            let n = notes[week % notes.count]
            plans.append(Plan(daysAgo: base + 1, hour: 6, minute: 40, kilometers: 5 + Double(week % 3),
                              pace: 352 - Double(9 - week) * 1.5, name: nil, intervals: false,
                              feeling: .good, surface: .road, notes: n))
            if week == 3 {
                plans.append(Plan(daysAgo: base + 3, hour: 7, minute: 0, kilometers: 5, pace: 288,
                                  name: "5K Race", intervals: false, feeling: .great, surface: .road,
                                  notes: "Parque do Ibirapuera 5K. New PR!"))
            } else {
                plans.append(Plan(daysAgo: base + 3, hour: 19, minute: 10, kilometers: 7, pace: 326,
                                  name: week.isMultiple(of: 2) ? "8 × 400 m" : nil, intervals: week.isMultiple(of: 2),
                                  feeling: week.isMultiple(of: 3) ? .tough : .good, surface: week.isMultiple(of: 2) ? .track : .road, notes: ""))
            }
            plans.append(Plan(daysAgo: base + 5, hour: 7, minute: 15, kilometers: 10 + Double(10 - week) * 0.8,
                              pace: 368, name: "Long Run", intervals: false,
                              feeling: week == 0 ? .great : .okay, surface: .mixed, notes: week == 0 ? "Longest run so far." : ""))
        }
        return plans
    }

    /// A lap-shaped route at roughly `pace`, one point every 4 seconds, with heart rate.
    private static func route(start: Date, meters: Double, pace: Double, center: Coordinate,
                              intervals: Bool, rng: inout SeededRandom) -> [RoutePoint] {
        let latScale = 111_320.0
        let lonScale = latScale * cos(center.latitude * .pi / 180)
        let radius = Double.random(in: 420...620, using: &rng)
        let squash = Double.random(in: 0.55...0.8, using: &rng)
        var theta = Double.random(in: 0..<(2 * .pi), using: &rng)

        func position(_ angle: Double) -> (lat: Double, lon: Double) {
            let r = radius * (1 + 0.16 * sin(3 * angle))
            return (center.latitude + r * sin(angle) * squash / latScale,
                    center.longitude + r * cos(angle) / lonScale)
        }

        let origin = position(theta)
        var points = [RoutePoint(latitude: origin.lat, longitude: origin.lon, altitude: 752 + 9 * sin(theta * 2),
                                 timestamp: start, heartRate: 105)]
        var covered = 0.0, elapsed = 0.0
        let step = 4.0
        while covered < meters {
            var p = pace * (1 + 0.04 * sin(covered / 1_300) + Double.random(in: -0.03...0.03, using: &rng))
            if intervals, covered > 1_500, covered < meters - 1_500 {
                p *= Int((covered - 1_500) / 400).isMultiple(of: 2) ? 0.82 : 1.25
            }
            let ds = 1_000 / p * step

            let here = position(theta)
            var dTheta = ds / radius
            let next = position(theta + dTheta)
            let actual = hypot((next.lat - here.lat) * latScale, (next.lon - here.lon) * lonScale)
            if actual > 0 { dTheta *= ds / actual }
            theta += dTheta

            let spot = position(theta)
            let progress = covered / meters
            let heartRate = min(192, 118 + (400 - p) * 0.38 + 12 * progress + Double.random(in: -3...3, using: &rng))
            points.append(RoutePoint(
                latitude: spot.lat,
                longitude: spot.lon,
                altitude: 752 + 9 * sin(theta * 2) + 4 * sin(covered / 450),
                // Stamped with the time the point was reached, one step after the previous one.
                timestamp: start.addingTimeInterval(elapsed + step),
                heartRate: heartRate
            ))
            covered += ds
            elapsed += step
        }
        return points
    }
}

/// SplitMix64: small, fast and deterministic.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
