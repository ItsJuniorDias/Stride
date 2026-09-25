import Foundation
import SwiftData

/// A run's heart rate: the average, time in each zone and the heart rate at every route point.
/// Kept in a store on this device only: App Store guideline 5.1.3(ii) doesn't allow health data in
/// iCloud, so it never travels with the synced ``Run``. Linked to its run by id.
@Model
public final class RunVitals {
    public var runID: UUID = UUID()
    public var averageHeartRate: Double?
    /// Seconds per heart-rate zone, keyed by zone number.
    public var zoneData: Data?
    /// Heart rate per route point, in route order (nil where there was none).
    public var heartRatesData: Data?

    public init(runID: UUID, averageHeartRate: Double? = nil) {
        self.runID = runID
        self.averageHeartRate = averageHeartRate
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

    public var heartRates: [Double?] {
        get { heartRatesData.flatMap { try? JSONDecoder().decode([Double?].self, from: $0) } ?? [] }
        set { heartRatesData = newValue.contains { $0 != nil } ? try? JSONEncoder().encode(newValue) : nil }
    }

    /// Whether there's anything to keep.
    public var isEmpty: Bool {
        averageHeartRate == nil && zoneData == nil && heartRatesData == nil
    }

    /// A route without its heart rates (what the synced run keeps), and the heart rates in order.
    public static func split(_ route: [RoutePoint]) -> (route: [RoutePoint], heartRates: [Double?]) {
        let heartRates = route.map(\.heartRate)
        var stripped = route
        for index in stripped.indices { stripped[index].heartRate = nil }
        return (stripped, heartRates)
    }

    /// The route with its heart rates put back, when they line up.
    public static func merge(_ route: [RoutePoint], heartRates: [Double?]) -> [RoutePoint] {
        guard heartRates.count == route.count else { return route }
        var merged = route
        for index in merged.indices { merged[index].heartRate = heartRates[index] }
        return merged
    }

    /// The vitals of a run recorded on Apple Watch.
    public convenience init(transfer: RunTransfer) {
        self.init(runID: transfer.id, averageHeartRate: transfer.averageHeartRate)
        zoneSeconds = transfer.zones
        heartRates = transfer.route.map(\.heartRate)
    }
}
