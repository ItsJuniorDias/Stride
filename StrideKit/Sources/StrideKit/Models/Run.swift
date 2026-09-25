import Foundation
import SwiftData

@Model
public final class Run {
    public var id: UUID = UUID()
    public var startDate: Date = Date.now
    /// Moving time in seconds, pauses excluded.
    public var duration: TimeInterval = 0
    /// Meters.
    public var distance: Double = 0
    /// Kilocalories.
    public var calories: Double = 0
    public var elevationGain: Double = 0
    public var elevationLoss: Double = 0
    public var averageHeartRate: Double?
    public var typeRaw: String = RunType.free.rawValue
    /// Name of the workout or plan session, if the run followed one.
    public var workoutName: String?
    public var feelingRaw: Int?
    public var surfaceRaw: String?
    public var notes: String = ""
    public var isManual: Bool = false
    @Attribute(.externalStorage) public var routeData: Data?
    /// Splits per kilometer, computed when the run is saved.
    public var splitsData: Data?
    /// A downsampled route for list thumbnails, so lists never decode the full route.
    public var previewData: Data?
    /// Seconds per heart-rate zone, keyed by zone number, when heart rate was recorded.
    public var zoneData: Data?
    /// The training-plan session this run completed, if any.
    public var planSessionID: String?
    /// Where the run was recorded: "iphone" or "watch".
    public var sourceRaw: String = RunSource.iPhone.rawValue
    public var shoe: Shoe?
    /// Fastest seconds over standard distances within this run, keyed by ``EffortDistance`` raw value.
    public var bestEffortsData: Data?
    /// The ``BestEfforts/version`` the stored efforts were computed with; 0 when never computed.
    public var effortsVersion: Int = 0

    public init(
        startDate: Date,
        duration: TimeInterval,
        distance: Double,
        calories: Double = 0,
        type: RunType = .free,
        isManual: Bool = false
    ) {
        self.startDate = startDate
        self.duration = duration
        self.distance = distance
        self.calories = calories
        self.typeRaw = type.rawValue
        self.isManual = isManual
    }

    public var endDate: Date { startDate.addingTimeInterval(duration) }

    public var type: RunType {
        get { RunType(rawValue: typeRaw) ?? .free }
        set { typeRaw = newValue.rawValue }
    }

    public var feeling: Feeling? {
        get { feelingRaw.flatMap(Feeling.init(rawValue:)) }
        set { feelingRaw = newValue?.rawValue }
    }

    public var surface: Surface? {
        get { surfaceRaw.flatMap(Surface.init(rawValue:)) }
        set { surfaceRaw = newValue?.rawValue }
    }

    /// The full GPS route. Decodes on every read; cache it in the view.
    public var route: [RoutePoint] {
        get { routeData.flatMap { try? JSONDecoder().decode([RoutePoint].self, from: $0) } ?? [] }
        set {
            routeData = try? JSONEncoder().encode(newValue)
            previewData = try? JSONEncoder().encode(RouteAnalysis.preview(of: newValue))
        }
    }

    public var splits: [Split] {
        get { splitsData.flatMap { try? JSONDecoder().decode([Split].self, from: $0) } ?? [] }
        set { splitsData = try? JSONEncoder().encode(newValue) }
    }

    public var source: RunSource {
        get { RunSource(rawValue: sourceRaw) ?? .iPhone }
        set { sourceRaw = newValue.rawValue }
    }

    public var zoneSeconds: [HeartRateZone: TimeInterval] {
        get {
            let raw = zoneData.flatMap { try? JSONDecoder().decode([Int: TimeInterval].self, from: $0) } ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in HeartRateZone(rawValue: key).map { ($0, value) } })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            zoneData = raw.isEmpty ? nil : try? JSONEncoder().encode(raw)
        }
    }

    public var bestEfforts: [EffortDistance: TimeInterval] {
        get {
            let raw = bestEffortsData.flatMap { try? JSONDecoder().decode([Int: TimeInterval].self, from: $0) } ?? [:]
            return Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in EffortDistance(rawValue: key).map { ($0, value) } })
        }
        set {
            let raw = Dictionary(uniqueKeysWithValues: newValue.map { ($0.key.rawValue, $0.value) })
            bestEffortsData = try? JSONEncoder().encode(raw)
        }
    }

    /// Recomputes the best efforts from the route (pass it when already decoded) and the run's final
    /// distance and time. Call after those are set.
    public func updateBestEfforts(route points: [RoutePoint]? = nil) {
        bestEfforts = BestEfforts.compute(route: points ?? route, distance: distance, duration: duration, typed: isManual)
        effortsVersion = BestEfforts.version
    }

    /// The numbers stats, streaks and challenges use.
    public var sample: RunSample {
        RunSample(date: startDate, distance: distance, duration: duration, elevationGain: elevationGain, calories: calories)
    }

    /// What personal records use. Decodes the stored efforts; cache the result for lists.
    public var recordEntry: RecordEntry {
        RecordEntry(id: id, date: startDate, distance: distance, duration: duration, elevationGain: elevationGain, efforts: bestEfforts)
    }

    public var preview: [Coordinate] {
        previewData.flatMap { try? JSONDecoder().decode([Coordinate].self, from: $0) } ?? []
    }

    public func averagePace(in unit: UnitSystem) -> Double? {
        RunFormat.paceSeconds(distance: distance, duration: duration, unit: unit)
    }

    /// Splits in the given unit: the stored kilometer splits, or recomputed from the route for miles.
    public func splits(in unit: UnitSystem) -> [Split] {
        guard unit != .metric else { return splits }
        let points = route
        return RouteAnalysis.splits(from: points, unit: unit, scale: Self.splitScale(distance: distance, route: points, source: source))
    }

    /// Charts for Watch runs match Apple Watch's average speed rather than its total distance: the route
    /// can start late (GPS lock) or miss a stretch, and stretching by distance would make every
    /// stretch look faster than it was.
    static func chartScale(distance: Double, duration: TimeInterval, route: [RoutePoint], source: RunSource) -> Double {
        guard source == .watch else { return 1 }
        let routeDistance = RouteAnalysis.distance(of: route)
        let routeTime = RouteAnalysis.movingTime(of: route)
        guard routeDistance > 0, routeTime > 0, distance > 0, duration > 0 else { return 1 }
        return min(max((distance / duration) / (routeDistance / routeTime), 0.5), 2)
    }

    /// Watch runs report Apple Watch's workout distance, which is more accurate than the raw GPS route;
    /// splits are stretched to add up to it. iPhone runs use the route as recorded.
    static func splitScale(distance: Double, route: [RoutePoint], source: RunSource) -> Double {
        guard source == .watch else { return 1 }
        let routeDistance = RouteAnalysis.distance(of: route)
        guard routeDistance > 0, distance > 0 else { return 1 }
        return min(max(distance / routeDistance, 0.5), 2)
    }

    /// The workout name, or a time-of-day title like "Morning Run".
    public var title: String {
        if let workoutName, !workoutName.isEmpty { return workoutName }
        return Self.timeOfDayTitle(for: startDate)
    }

    /// "Morning Run", "Lunch Run", "Afternoon Run", "Evening Run" or "Night Run".
    public static func timeOfDayTitle(for date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<11: "Morning Run"
        case 11..<14: "Lunch Run"
        case 14..<18: "Afternoon Run"
        case 18..<22: "Evening Run"
        default: "Night Run"
        }
    }

    /// Fills distance, duration, elevation, heart rate, splits and preview from a recorded route.
    public func apply(route points: [RoutePoint], weightKg: Double) {
        route = points
        distance = RouteAnalysis.distance(of: points)
        duration = RouteAnalysis.movingTime(of: points)
        let elevation = RouteAnalysis.elevation(of: points)
        elevationGain = elevation.gain
        elevationLoss = elevation.loss
        let rates = points.compactMap(\.heartRate)
        averageHeartRate = rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count)
        if !rates.isEmpty {
            zoneSeconds = RouteAnalysis.zoneSeconds(of: points, maxHeartRate: HeartRateZone.defaultMaxHeartRate)
        }
        calories = Self.estimatedCalories(distance: distance, weightKg: weightKg)
        splits = RouteAnalysis.splits(from: points, unit: .metric)
    }

    /// Creates the run for a workout recorded on Apple Watch.
    public convenience init(transfer: RunTransfer) {
        self.init(startDate: transfer.startDate, duration: transfer.duration, distance: transfer.distance,
                  calories: transfer.calories, type: transfer.type)
        id = transfer.id
        source = .watch
        workoutName = transfer.workoutName
        averageHeartRate = transfer.averageHeartRate
        zoneSeconds = transfer.zones
        if transfer.route.count > 1 {
            route = transfer.route
            let scale = Self.splitScale(distance: transfer.distance, route: transfer.route, source: .watch)
            splits = RouteAnalysis.splits(from: transfer.route, unit: .metric, scale: scale)
            let elevation = RouteAnalysis.elevation(of: transfer.route)
            elevationGain = elevation.gain
            elevationLoss = elevation.loss
        }
        updateBestEfforts(route: transfer.route)
    }

    /// Running costs roughly 1.036 kcal per kg per km.
    public static func estimatedCalories(distance meters: Double, weightKg: Double) -> Double {
        weightKg * meters / 1_000 * 1.036
    }
}
