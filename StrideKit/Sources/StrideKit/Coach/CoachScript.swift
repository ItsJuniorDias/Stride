import Foundation

/// What the voice coach says. Plain facts first, encouragement last, never longer than one breath.
public enum CoachScript {
    public static func spokenDuration(_ seconds: TimeInterval) -> String {
        let total = Int(max(seconds, 0).rounded())
        let h = total / 3_600, m = (total % 3_600) / 60, s = total % 60
        var parts: [String] = []
        if h > 0 { parts.append("\(h) \(h == 1 ? "hour" : "hours")") }
        if m > 0 { parts.append("\(m) \(m == 1 ? "minute" : "minutes")") }
        if s > 0 || parts.isEmpty { parts.append("\(s) \(s == 1 ? "second" : "seconds")") }
        return parts.joined(separator: " ")
    }

    public static func spokenDistance(_ meters: Double, unit: UnitSystem) -> String {
        let value = meters / unit.metersPerUnit
        let rounded = (value * 100).rounded() / 100
        let number = rounded == rounded.rounded() ? "\(Int(rounded))" : rounded.formatted(.number.precision(.fractionLength(0...2)).locale(Locale(identifier: "en_US")))
        let name = unit == .metric ? (rounded == 1 ? "kilometer" : "kilometers") : (rounded == 1 ? "mile" : "miles")
        return "\(number) \(name)"
    }

    public static func spokenPace(_ secondsPerUnit: Double, unit: UnitSystem) -> String {
        "\(spokenDuration(secondsPerUnit)) per \(unit == .metric ? "kilometer" : "mile")"
    }

    /// Short step goal, e.g. "400 meters" or "90 seconds".
    public static func spokenGoal(_ goal: WorkoutStep.Goal, unit: UnitSystem) -> String {
        switch goal {
        case .time(let seconds): return spokenDuration(seconds)
        case .distance(let meters):
            return meters < 1_000 && unit == .metric ? "\(Int(meters)) meters" : spokenDistance(meters, unit: unit)
        }
    }

    public static func start(workout: Workout?) -> String {
        guard let workout else { return "Run started." }
        return "\(workout.name). Let's go."
    }

    /// "2 kilometers. Time 11 minutes 4 seconds. Average pace 5 minutes 32 seconds per kilometer."
    /// `splitLength` is the announcement interval in units; the last split is named after it.
    public static func split(distance: Double, elapsed: TimeInterval, averagePace: Double?, lastSplitPace: Double?,
                             unit: UnitSystem, splitLength: Double = 1,
                             includeTime: Bool = true, includePace: Bool = true) -> String {
        var sentences = [spokenDistance(distance, unit: unit).capitalizedFirst + "."]
        if includeTime { sentences.append("Time \(spokenDuration(elapsed)).") }
        if includePace, let averagePace { sentences.append("Average pace \(spokenPace(averagePace, unit: unit)).") }
        if includePace, let lastSplitPace, lastSplitPace != averagePace {
            if splitLength == 1 {
                sentences.append("Last \(unit == .metric ? "kilometer" : "mile") \(spokenDuration(lastSplitPace)).")
            } else {
                let length = spokenGoal(.distance(splitLength * unit.metersPerUnit), unit: unit)
                sentences.append("Last \(length) at \(spokenPace(lastSplitPace, unit: unit)).")
            }
        }
        return sentences.joined(separator: " ")
    }

    public static func stepStarted(_ step: WorkoutStep, in workout: Workout, unit: UnitSystem) -> String {
        let goal = spokenGoal(step.goal, unit: unit)
        switch step.kind {
        case .warmup: return "Warm up for \(goal)."
        case .cooldown: return "Last step. Cool down for \(goal)."
        case .recover: return "Recover. \(goal.capitalizedFirst) easy."
        case .run:
            let total = workout.runStepCount
            if total > 1, let number = workout.runNumber(of: step) {
                return "Interval \(number) of \(total). Run \(goal)."
            }
            return "Run \(goal)."
        }
    }

    public static let workoutCompleted = "Workout complete. Great work. Keep going or finish when you're ready."

    public static func goalHalfway(remaining: String) -> String {
        "Halfway there. \(remaining.capitalizedFirst) to go."
    }

    public static let goalReached = "Goal reached. Nice running."

    public static func pace(_ status: PaceGuard.Status, unit: UnitSystem) -> String {
        let per = unit == .metric ? "kilometer" : "mile"
        switch status {
        case .onPace: return "Back on pace."
        case .tooSlow(let seconds): return "Speed up. You're \(Int(seconds.rounded())) seconds per \(per) behind your target."
        case .tooFast(let seconds): return "Ease off. You're \(Int(seconds.rounded())) seconds per \(per) ahead of your target."
        }
    }

    public static let paused = "Run paused."
    public static let resumed = "Run resumed."
    public static let autoPaused = "Auto-paused."
    public static let autoResumed = "Resumed."

    public static func finished(distance: Double, elapsed: TimeInterval, unit: UnitSystem) -> String {
        "Run finished. \(spokenDistance(distance, unit: unit).capitalizedFirst) in \(spokenDuration(elapsed)). Well done."
    }
}

private extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
