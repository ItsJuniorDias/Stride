import Foundation

/// A race time the runner could run today, predicted from one of their best efforts.
public struct RacePrediction: Hashable, Sendable, Identifiable {
    /// The race.
    public let distance: EffortDistance
    /// Predicted finish time, in seconds.
    public let time: TimeInterval
    /// The best effort the prediction comes from.
    public let source: EffortDistance
    /// That effort's time, in seconds.
    public let sourceTime: TimeInterval
    /// When that effort was run, and in which run.
    public let sourceDate: Date
    public let runID: UUID

    public var id: Int { distance.rawValue }

    /// Seconds per kilometer or mile at the predicted time.
    public func pace(in unit: UnitSystem) -> Double? {
        RunFormat.paceSeconds(distance: distance.meters, duration: time, unit: unit)
    }
}

/// The runner's race predictions, and which best efforts they come from.
public struct RacePredictions: Hashable, Sendable {
    /// Which best efforts the predictions use.
    public enum Basis: Hashable, Sendable {
        /// The last ``RacePredictor/recentDays`` days: how the runner runs today.
        case recent
        /// Too few runs lately, so the best efforts ever. Likely faster than the runner is today.
        case allTime
    }

    public let basis: Basis
    /// By race, for each of ``RacePredictor/races`` the efforts can credibly predict.
    public let predictions: [EffortDistance: RacePrediction]
    /// Seconds for 5 km at the runner's current fitness: the 5K prediction. Every effort can predict
    /// a 5K, so there always is one. Plans derive their paces from it (see ``TrainingPaces``).
    public let fiveKEquivalent: TimeInterval

    public subscript(race: EffortDistance) -> RacePrediction? { predictions[race] }

    /// Paces for each kind of run, from ``fiveKEquivalent``.
    public var trainingPaces: TrainingPaces? { TrainingPaces(fiveKTime: fiveKEquivalent) }
}

/// Predicts race times with Riegel's formula, T₂ = T₁ × (D₂ / D₁)^1.06, from the runner's best efforts
/// (see ``BestEfforts``).
///
/// The fastest effort of each distance from the last ``recentDays`` days predicts every race within
/// ``maximumRatio`` of it. The fastest prediction wins, after a small handicap per doubling of distance
/// between effort and race: Riegel gets less reliable the further it reaches, so a near tie goes to
/// the closer effort while a clearly faster one still counts.
public enum RacePredictor {
    /// The races predicted, shortest first.
    public static let races: [EffortDistance] = [.fiveK, .tenK, .half, .marathon]
    /// Riegel's fatigue exponent.
    public static let exponent = 1.06
    /// How far back "how you run today" reaches.
    public static let recentDays = 120
    /// Runs with a best effort needed before predicting anything: one easy jog says little about a race.
    public static let minimumRuns = 3
    /// Efforts shorter than 1 km say more about speed than endurance.
    static let shortestSource = 1_000.0
    /// The furthest a prediction reaches, as a ratio of distances either way: a 5K can predict a
    /// marathon (8.4×), a mile can't predict a half (13×).
    static let maximumRatio = 8.5
    /// Handicap per doubling of distance between effort and race, used only to choose between predictions.
    static let handicapPerDoubling = 0.03

    /// Riegel's prediction for `target` meters from `time` seconds over `distance` meters.
    public static func riegel(_ time: TimeInterval, from distance: Double, to target: Double) -> TimeInterval {
        guard distance > 0, target > 0 else { return .nan }
        return time * pow(target / distance, exponent)
    }

    /// Whether a best effort over `effort` is close enough to `race` to predict it. Never a marathon
    /// from under 5 km.
    public static func canPredict(_ race: EffortDistance, from effort: EffortDistance) -> Bool {
        let ratio = race.meters / effort.meters
        return effort.meters >= shortestSource && ratio <= maximumRatio && ratio >= 1 / maximumRatio
    }

    /// The shortest best effort that can predict `race`, to tell the runner what to run: a 5K for the
    /// half and marathon, a mile for the 10K.
    public static func shortestEffort(for race: EffortDistance) -> EffortDistance? {
        EffortDistance.allCases.sorted { $0.meters < $1.meters }.first { canPredict(race, from: $0) }
    }

    /// Predictions from the best efforts of the last ``recentDays`` days, or from the best efforts
    /// ever when there are fewer than ``minimumRuns`` recent runs with one. Nil until there are
    /// enough runs either way.
    public static func predict(from entries: [RecordEntry], now: Date = .now, calendar: Calendar = .current) -> RacePredictions? {
        let start = calendar.date(byAdding: .day, value: -recentDays, to: now)
            ?? now.addingTimeInterval(-Double(recentDays) * 86_400)
        // No upper bound: a run saved after `now` was taken is still recent.
        return predictions(from: entries.filter { $0.date >= start }, basis: .recent)
            ?? predictions(from: entries, basis: .allTime)
    }

    /// Seconds for 5 km at the runner's current fitness (see ``RacePredictions/fiveKEquivalent``).
    public static func fiveKEquivalent(from entries: [RecordEntry], now: Date = .now,
                                       calendar: Calendar = .current) -> TimeInterval? {
        predict(from: entries, now: now, calendar: calendar)?.fiveKEquivalent
    }

    private struct Effort {
        let time: TimeInterval
        let date: Date
        let runID: UUID
    }

    static func predictions(from entries: [RecordEntry], basis: RacePredictions.Basis) -> RacePredictions? {
        // The fastest effort of each distance; a tie goes to the earlier run, as with records.
        var best: [EffortDistance: Effort] = [:]
        var runs = 0
        for entry in entries {
            var counted = false
            for (distance, time) in entry.efforts where distance.meters >= shortestSource && time.isFinite && time > 0 {
                counted = true
                if let current = best[distance], current.time < time || (current.time == time && current.date <= entry.date) {
                    continue
                }
                best[distance] = Effort(time: time, date: entry.date, runID: entry.id)
            }
            if counted { runs += 1 }
        }
        guard runs >= minimumRuns else { return nil }

        var predictions: [EffortDistance: RacePrediction] = [:]
        for race in races {
            var chosen: (prediction: RacePrediction, score: Double)?
            // Shortest effort first, so an exact tie is settled the same way every time.
            for source in EffortDistance.allCases where canPredict(race, from: source) {
                guard let effort = best[source] else { continue }
                let time = riegel(effort.time, from: source.meters, to: race.meters)
                // Faster than about the world record isn't credible.
                guard time.isFinite, time >= BestEfforts.fastestPlausible(race) else { continue }
                let score = time * (1 + handicapPerDoubling * abs(log2(race.meters / source.meters)))
                if let current = chosen, current.score <= score { continue }
                let prediction = RacePrediction(distance: race, time: time, source: source, sourceTime: effort.time,
                                                sourceDate: effort.date, runID: effort.runID)
                chosen = (prediction, score)
            }
            if let chosen { predictions[race] = chosen.prediction }
        }
        guard let fiveK = predictions[.fiveK]?.time else { return nil }
        return RacePredictions(basis: basis, predictions: predictions, fiveKEquivalent: fiveK)
    }
}
