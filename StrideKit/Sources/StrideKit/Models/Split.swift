import Foundation

/// One kilometer (or mile) of a run. The last split of a run may be partial.
public struct Split: Codable, Hashable, Identifiable, Sendable {
    public var index: Int
    /// Meters covered in this split.
    public var distance: Double
    /// Moving time in seconds.
    public var duration: TimeInterval
    /// Altitude at the end minus altitude at the start, in meters.
    public var elevationDelta: Double

    public var id: Int { index }

    public init(index: Int, distance: Double, duration: TimeInterval, elevationDelta: Double = 0) {
        self.index = index
        self.distance = distance
        self.duration = duration
        self.elevationDelta = elevationDelta
    }

    public func pace(in unit: UnitSystem) -> Double? {
        RunFormat.paceSeconds(distance: distance, duration: duration, unit: unit)
    }

    /// A split shorter than a full unit, the tail end of a run.
    public func isPartial(in unit: UnitSystem) -> Bool {
        distance < unit.metersPerUnit * 0.99
    }

    /// The fastest full split, if any. Partial splits never count as fastest.
    public static func fastest(in splits: [Split], unit: UnitSystem) -> Split? {
        splits
            .filter { !$0.isPartial(in: unit) }
            .min { ($0.pace(in: unit) ?? .infinity) < ($1.pace(in: unit) ?? .infinity) }
    }
}
