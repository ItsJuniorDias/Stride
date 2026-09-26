import Foundation

/// The shape the workout builder makes: an optional warm-up, a block of repeats (a run, and a
/// recovery between runs) and an optional cool-down. Custom workouts store the steps this makes, so a
/// richer builder later needs no schema change; ``init(steps:)`` reads them back for editing.
public struct WorkoutBlueprint: Hashable, Sendable {
    public var warmup: WorkoutStep.Goal?
    public var repeats: Int
    public var work: WorkoutStep.Goal
    /// Seconds per kilometer to hold on every run, like ``WorkoutStep/targetPace``.
    public var workPace: Double?
    /// Between runs; a single repeat has none.
    public var recovery: WorkoutStep.Goal?
    public var cooldown: WorkoutStep.Goal?

    public static let repeatRange = 1...30

    public init(warmup: WorkoutStep.Goal?, repeats: Int, work: WorkoutStep.Goal, workPace: Double? = nil,
                recovery: WorkoutStep.Goal?, cooldown: WorkoutStep.Goal?) {
        self.warmup = warmup
        self.repeats = repeats
        self.work = work
        self.workPace = workPace
        self.recovery = recovery
        self.cooldown = cooldown
    }

    /// Where a new workout starts: 10 min warm-up, 6 × 800 m with 2 min recoveries, 5 min cool-down.
    public static let starter = WorkoutBlueprint(warmup: .time(600), repeats: 6, work: .distance(800),
                                                 recovery: .time(120), cooldown: .time(300))

    /// The steps to follow, in order, the way ``Workout/intervals(id:name:detail:warmup:repeats:work:rest:cooldown:)``
    /// lays them out.
    public var steps: [WorkoutStep] {
        Workout.intervals(id: "", name: "", detail: "",
                          warmup: warmup.map { WorkoutStep(.warmup, $0) },
                          repeats: min(max(repeats, Self.repeatRange.lowerBound), Self.repeatRange.upperBound),
                          work: WorkoutStep(.run, work, targetPace: workPace),
                          rest: recovery.map { WorkoutStep(.recover, $0) },
                          cooldown: cooldown.map { WorkoutStep(.cooldown, $0) }).steps
    }

    /// Reads steps back into the builder's shape. Nil for steps it can't make, e.g. runs of different
    /// lengths, which then run fine but can't be edited here.
    public init?(steps: [WorkoutStep]) {
        var middle = steps[...]
        var warmup: WorkoutStep.Goal?
        if let first = middle.first, first.kind == .warmup {
            warmup = first.goal
            middle = middle.dropFirst()
        }
        var cooldown: WorkoutStep.Goal?
        if let last = middle.last, last.kind == .cooldown {
            cooldown = last.goal
            middle = middle.dropLast()
        }
        let runs = middle.filter { $0.kind == .run }
        let recoveries = middle.filter { $0.kind == .recover }
        guard let work = runs.first, Self.repeatRange.contains(runs.count),
              runs.allSatisfy({ $0.goal == work.goal && $0.targetPace == work.targetPace }),
              recoveries.allSatisfy({ $0.goal == recoveries.first?.goal })
        else { return nil }
        let blueprint = WorkoutBlueprint(warmup: warmup, repeats: runs.count, work: work.goal, workPace: work.targetPace,
                                         recovery: recoveries.first?.goal, cooldown: cooldown)
        // Run, recover, run, …, run: exactly what the builder lays out, and nothing else.
        guard blueprint.steps.map(\.kind) == steps.map(\.kind) else { return nil }
        self = blueprint
    }

    // MARK: Words

    /// "6 × 800 m", or "20 min run" for a single repeat: the name when the runner doesn't give one.
    public func defaultName(unit: UnitSystem) -> String {
        let work = Self.text(for: work, unit: unit)
        return repeats > 1 ? "\(repeats) × \(work)" : "\(work) run"
    }

    /// "6 × 800 m at 4'50" /km, 2 min recoveries · Warm-up 10 min, cool-down 5 min".
    public func detail(unit: UnitSystem) -> String {
        var main = defaultName(unit: unit)
        if let workPace {
            main += " at \(RunFormat.pace(TrainingPaces.perUnit(workPace, unit: unit))) \(unit.paceSymbol)"
        }
        if repeats > 1, let recovery {
            main += ", \(Self.text(for: recovery, unit: unit)) recoveries"
        }
        let ends = [warmup.map { "warm-up \(Self.text(for: $0, unit: unit))" },
                    cooldown.map { "cool-down \(Self.text(for: $0, unit: unit))" }].compactMap { $0 }
        guard !ends.isEmpty else { return main }
        let extra = ends.joined(separator: ", ")
        return "\(main) · \(extra.prefix(1).uppercased())\(extra.dropFirst())"
    }

    /// A step's length in a few characters: "30 s", "90 s", "2 min", "2:30 min", "800 m", "1.5 km",
    /// "1 mi". With miles, only quarter miles read as miles; other distances are track distances, in meters.
    public static func text(for goal: WorkoutStep.Goal, unit: UnitSystem) -> String {
        switch goal {
        case .time(let seconds):
            // Clamped, so a damaged value can't overflow Int.
            let total = seconds.isFinite ? Int(min(max(seconds, 0), 360_000).rounded()) : 0
            if total < 60 || (total < 120 && total % 60 != 0) { return "\(total) s" }
            if total % 60 == 0 { return "\(total / 60) min" }
            return "\(RunFormat.duration(TimeInterval(total))) min"
        case .distance(let length):
            let meters = length.isFinite ? min(max(length, 0), 1_000_000) : 0
            if unit == .imperial {
                // Quarter miles read as miles; anything else is a track distance, in meters.
                let miles = meters / unit.metersPerUnit
                guard miles > 0.249, abs(miles * 4 - (miles * 4).rounded()) < 0.001 else { return "\(Int(meters.rounded())) m" }
                return "\(miles.formatted(.number.precision(.fractionLength(0...2)))) mi"
            }
            if meters < 1_000 { return "\(Int(meters.rounded())) m" }
            return "\((meters / 1_000).formatted(.number.precision(.fractionLength(0...2)))) km"
        }
    }
}

/// Roughly how long and how far a workout goes. Time steps are exact in time and distance steps in
/// distance; the other half comes from a pace: a run step's target if it has one, otherwise
/// `runPace`, and `easyPace` for warm-ups, recoveries and cool-downs (seconds per kilometer).
public struct WorkoutEstimate: Hashable, Sendable {
    public let duration: TimeInterval
    /// Meters.
    public let distance: Double
    /// Seconds per step, in order, for drawing the workout's shape.
    public let stepDurations: [TimeInterval]
    /// Every step is timed, so ``duration`` is exact.
    public let isDurationExact: Bool
    /// Every step is a distance, so ``distance`` is exact.
    public let isDistanceExact: Bool

    /// Paces for an estimate without the runner's own: 6'30" per km easy, 5'30" per km for runs.
    public static let typicalEasyPace = 390.0
    public static let typicalRunPace = 330.0

    public init(steps: [WorkoutStep], easyPace: Double = WorkoutEstimate.typicalEasyPace,
                runPace: Double = WorkoutEstimate.typicalRunPace) {
        var durations: [TimeInterval] = []
        var distance = 0.0
        for step in steps {
            let pace = max(step.kind == .run ? step.targetPace ?? runPace : easyPace, 1)
            switch step.goal {
            case .time(let value):
                let seconds = value.isFinite ? max(value, 0) : 0
                durations.append(seconds)
                distance += seconds / pace * 1_000
            case .distance(let value):
                let meters = value.isFinite ? max(value, 0) : 0
                durations.append(meters / 1_000 * pace)
                distance += meters
            }
        }
        self.stepDurations = durations
        self.duration = durations.reduce(0, +)
        self.distance = distance
        self.isDurationExact = steps.allSatisfy(\.goal.isTime)
        self.isDistanceExact = !steps.contains(where: \.goal.isTime)
    }

    /// With the runner's paces: easy running for the easy parts, and for runs without a target the
    /// pace that suits their length.
    public init(steps: [WorkoutStep], paces: TrainingPaces) {
        let work = steps.first { $0.kind == .run }?.goal
        self.init(steps: steps, easyPace: paces.pace(.easy),
                  runPace: work.map { paces.pace(.suited(to: $0)) } ?? paces.interval)
    }
}

private extension WorkoutStep.Goal {
    var isTime: Bool {
        if case .time = self { return true }
        return false
    }
}
