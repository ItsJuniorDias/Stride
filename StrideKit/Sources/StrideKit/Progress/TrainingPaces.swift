import Foundation

/// Paces for each kind of run, from a 5K time, in seconds per kilometer like
/// ``WorkoutStep/targetPace``. Ratios to 5K race pace follow common coaching tables: easy 1.25–1.35×,
/// marathon by Riegel (about 1.14×), tempo 1.08×, interval 1.0× and repetition 0.95×.
///
/// Get the 5K time from ``RacePredictor/fiveKEquivalent(from:now:calendar:)`` or
/// ``RacePredictions/trainingPaces``.
public struct TrainingPaces: Hashable, Sendable {
    /// A kind of run, easiest first.
    public enum Intensity: String, CaseIterable, Identifiable, Sendable {
        /// Conversational: most of the week's running, and long runs.
        case easy
        /// Race pace for a marathon: steady long efforts.
        case marathon
        /// Comfortably hard, about the pace of an hour's race: tempo runs and threshold repeats.
        case threshold
        /// About 5K race pace: repeats of 2 to 5 minutes.
        case interval
        /// Faster than 5K pace: short repeats with full recoveries.
        case repetition

        public var id: Self { self }

        public var title: String {
            switch self {
            case .easy: "Easy"
            case .marathon: "Marathon"
            case .threshold: "Tempo"
            case .interval: "Interval"
            case .repetition: "Repetition"
            }
        }

        /// What the pace is for, in a few words.
        public var detail: String {
            switch self {
            case .easy: "Most of your runs"
            case .marathon: "Long, steady efforts"
            case .threshold: "Comfortably hard"
            case .interval: "Repeats of 2 to 5 minutes"
            case .repetition: "Short, fast repeats"
            }
        }
    }

    /// The 5K time the paces come from, in seconds.
    public let fiveKTime: TimeInterval

    /// Nil for a time that isn't a plausible 5K run: under 10 minutes or over 2 hours.
    public init?(fiveKTime: TimeInterval) {
        guard fiveKTime.isFinite, (600...7_200).contains(fiveKTime) else { return nil }
        self.fiveKTime = fiveKTime
    }

    /// 5K race pace, seconds per kilometer.
    public var fiveKPace: Double { fiveKTime / 5 }

    /// Easy runs span a range; the faster end is the lower bound.
    public var easy: ClosedRange<Double> { fiveKPace * 1.25 ... fiveKPace * 1.35 }

    /// The marathon the 5K predicts, as a pace.
    public var marathon: Double {
        RacePredictor.riegel(fiveKTime, from: EffortDistance.fiveK.meters, to: EffortDistance.marathon.meters)
            / (EffortDistance.marathon.meters / 1_000)
    }

    public var threshold: Double { fiveKPace * 1.08 }

    public var interval: Double { fiveKPace }

    public var repetition: Double { fiveKPace * 0.95 }

    /// The pace for `intensity` as a range, faster end first. Only easy spans one; the others are a
    /// single pace.
    public func range(_ intensity: Intensity) -> ClosedRange<Double> {
        switch intensity {
        case .easy: easy
        case .marathon: marathon...marathon
        case .threshold: threshold...threshold
        case .interval: interval...interval
        case .repetition: repetition...repetition
        }
    }

    /// One pace for `intensity`, for a target: the middle of the easy range.
    public func pace(_ intensity: Intensity) -> Double {
        let bounds = range(intensity)
        return (bounds.lowerBound + bounds.upperBound) / 2
    }

    /// Seconds per kilometer as seconds per the runner's unit, for display.
    public static func perUnit(_ secondsPerKilometer: Double, unit: UnitSystem) -> Double {
        secondsPerKilometer * unit.metersPerUnit / 1_000
    }
}
