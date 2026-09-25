import Foundation

/// Formatting rules from the design system's "Voice and copy" section:
/// pace `5'12"`, time `48:31` or `1:02:07`, empty values `--`.
public enum RunFormat {
    public static let empty = "--"

    /// Distance in the unit system, without the unit symbol.
    public static func distance(_ meters: Double, unit: UnitSystem, fractionDigits: Int = 2) -> String {
        let value = max(meters, 0) / unit.metersPerUnit
        return value.formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// Elapsed time: `m:ss` under an hour, `h:mm:ss` from an hour on.
    public static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return empty }
        let total = Int(seconds.rounded(.down))
        let h = total / 3_600, m = (total % 3_600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    /// Pace as minutes and seconds per unit, e.g. `5'12"`. Returns `--` for missing or implausible values.
    public static func pace(_ secondsPerUnit: Double?) -> String {
        guard let secondsPerUnit, secondsPerUnit.isFinite, secondsPerUnit > 0, secondsPerUnit < 3_600 else {
            return empty
        }
        let total = Int(secondsPerUnit.rounded())
        return String(format: "%d'%02d\"", total / 60, total % 60)
    }

    /// Seconds per unit for a distance covered in a duration, or nil when too short to be meaningful.
    public static func paceSeconds(distance meters: Double, duration: TimeInterval, unit: UnitSystem) -> Double? {
        guard meters >= 10, duration > 0 else { return nil }
        return duration / (meters / unit.metersPerUnit)
    }

    /// Signed elevation change, e.g. `+12 m` or `−6 m` (true minus sign).
    public static func elevationDelta(_ meters: Double, unit: UnitSystem) -> String {
        let value = Int(unit.elevation(fromMeters: meters).rounded())
        let sign = value > 0 ? "+" : value < 0 ? "−" : ""
        return "\(sign)\(abs(value)) \(unit.elevationSymbol)"
    }
}
