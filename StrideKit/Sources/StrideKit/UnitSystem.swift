import Foundation

/// Distance units the runner can choose. Everything is stored in meters and seconds;
/// the unit system only affects display, splits and voice feedback.
public enum UnitSystem: String, Codable, CaseIterable, Sendable {
    case metric
    case imperial

    public var metersPerUnit: Double {
        switch self {
        case .metric: 1_000
        case .imperial: 1_609.344
        }
    }

    public var distanceSymbol: String {
        switch self {
        case .metric: "km"
        case .imperial: "mi"
        }
    }

    public var paceSymbol: String { "/\(distanceSymbol)" }

    public var elevationSymbol: String {
        switch self {
        case .metric: "m"
        case .imperial: "ft"
        }
    }

    public func elevation(fromMeters meters: Double) -> Double {
        switch self {
        case .metric: meters
        case .imperial: meters * 3.280_84
        }
    }
}
