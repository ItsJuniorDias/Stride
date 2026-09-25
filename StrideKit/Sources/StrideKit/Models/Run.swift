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
    /// Where the run was recorded: "iphone" or "watch".
    public var sourceRaw: String = RunSource.iPhone.rawValue
    public var shoe: Shoe?

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
        switch Calendar.current.component(.hour, from: startDate) {
        case 5..<11: return "Morning Run"
        case 11..<14: return "Lunch Run"
        case 14..<18: return "Afternoon Run"
        case 18..<22: return "Evening Run"
        default: return "Night Run"
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
    }

    /// Running costs roughly 1.036 kcal per kg per km.
    public static func estimatedCalories(distance meters: Double, weightKg: Double) -> Double {
        weightKg * meters / 1_000 * 1.036
    }
}
