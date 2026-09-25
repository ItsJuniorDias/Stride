import Foundation

/// Five heart-rate zones as percentages of maximum heart rate (50/60/70/80/90%).
public enum HeartRateZone: Int, CaseIterable, Codable, Comparable, Sendable {
    case recovery = 1
    case easy
    case aerobic
    case threshold
    case maximum

    public var name: String {
        switch self {
        case .recovery: "Recovery"
        case .easy: "Easy"
        case .aerobic: "Aerobic"
        case .threshold: "Threshold"
        case .maximum: "Maximum"
        }
    }

    /// Lower bound of the zone as a fraction of max heart rate.
    public var lowerBound: Double {
        0.4 + Double(rawValue) * 0.1
    }

    /// The zone for a heart rate, or nil below 50% of max.
    public static func zone(for bpm: Double, maxHeartRate: Double) -> HeartRateZone? {
        guard maxHeartRate > 0 else { return nil }
        let fraction = bpm / maxHeartRate
        return allCases.last { fraction >= $0.lowerBound }
    }

    /// Estimated max heart rate (Tanaka: 208 − 0.7 × age).
    public static func estimatedMaxHeartRate(age: Int) -> Double {
        208 - 0.7 * Double(age)
    }

    public static func < (lhs: HeartRateZone, rhs: HeartRateZone) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
