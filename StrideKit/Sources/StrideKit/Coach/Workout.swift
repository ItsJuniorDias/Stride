import Foundation

/// One step of a structured workout: warm up for 10 minutes, run 400 m, recover 90 seconds…
public struct WorkoutStep: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case warmup, run, recover, cooldown

        public var title: String {
            switch self {
            case .warmup: "Warm-up"
            case .run: "Run"
            case .recover: "Recover"
            case .cooldown: "Cool-down"
            }
        }
    }

    public enum Goal: Codable, Hashable, Sendable {
        /// Seconds.
        case time(TimeInterval)
        /// Meters.
        case distance(Double)
    }

    /// Position in the workout; assigned by ``Workout``.
    public var id: Int
    public var kind: Kind
    public var goal: Goal
    /// Target pace in seconds per kilometer, for run steps that have one.
    public var targetPace: Double?

    public init(_ kind: Kind, _ goal: Goal, targetPace: Double? = nil) {
        self.id = 0
        self.kind = kind
        self.goal = goal
        self.targetPace = targetPace
    }

    public static func time(_ kind: Kind, minutes: Double) -> WorkoutStep {
        WorkoutStep(kind, .time(minutes * 60))
    }

    public static func time(_ kind: Kind, seconds: TimeInterval) -> WorkoutStep {
        WorkoutStep(kind, .time(seconds))
    }

    public static func distance(_ kind: Kind, meters: Double) -> WorkoutStep {
        WorkoutStep(kind, .distance(meters))
    }
}

/// A structured run: steps done in order. Used for interval sessions and training-plan sessions.
public struct Workout: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var name: String
    public var detail: String
    public var steps: [WorkoutStep]

    public init(id: String, name: String, detail: String, steps: [WorkoutStep]) {
        self.id = id
        self.name = name
        self.detail = detail
        self.steps = steps.enumerated().map { index, step in
            var step = step
            step.id = index
            return step
        }
    }

    /// Warm-up, `repeats` × (work, rest), cool-down. The last rest is dropped.
    public static func intervals(id: String, name: String, detail: String,
                                 warmup: WorkoutStep?, repeats: Int, work: WorkoutStep, rest: WorkoutStep?,
                                 cooldown: WorkoutStep?) -> Workout {
        var steps: [WorkoutStep] = []
        if let warmup { steps.append(warmup) }
        for index in 0..<repeats {
            steps.append(work)
            if let rest, index < repeats - 1 { steps.append(rest) }
        }
        if let cooldown { steps.append(cooldown) }
        return Workout(id: id, name: name, detail: detail, steps: steps)
    }

    /// How many work intervals (run steps) the workout has.
    public var runStepCount: Int { steps.filter { $0.kind == .run }.count }

    /// 1-based number of a run step among the run steps, e.g. "interval 3 of 8".
    public func runNumber(of step: WorkoutStep) -> Int? {
        guard step.kind == .run else { return nil }
        return steps.prefix(step.id + 1).filter { $0.kind == .run }.count
    }
}

/// Ready-made interval sessions offered on the run setup screen.
public enum IntervalPresets {
    private static let warmup = WorkoutStep.time(.warmup, minutes: 10)
    private static let cooldown = WorkoutStep.time(.cooldown, minutes: 5)

    public static let all: [Workout] = [
        .intervals(id: "preset-8x400", name: "8 × 400 m", detail: "Short, fast repeats with 90 s recoveries",
                   warmup: warmup, repeats: 8, work: .distance(.run, meters: 400), rest: .time(.recover, seconds: 90), cooldown: cooldown),
        .intervals(id: "preset-5x1k", name: "5 × 1 km", detail: "Threshold kilometers with 2 min recoveries",
                   warmup: warmup, repeats: 5, work: .distance(.run, meters: 1_000), rest: .time(.recover, minutes: 2), cooldown: cooldown),
        .intervals(id: "preset-fartlek", name: "Fartlek 30/30", detail: "10 × 30 s fast, 30 s easy",
                   warmup: warmup, repeats: 10, work: .time(.run, seconds: 30), rest: .time(.recover, seconds: 30), cooldown: cooldown),
        .intervals(id: "preset-4x4", name: "4 × 4 min", detail: "Hard 4-minute efforts with 3 min recoveries",
                   warmup: warmup, repeats: 4, work: .time(.run, minutes: 4), rest: .time(.recover, minutes: 3), cooldown: cooldown),
        Workout(id: "preset-pyramid", name: "Pyramid", detail: "1-2-3-2-1 minutes fast, 1 min easy between",
                steps: [warmup] + [1, 2, 3, 2, 1].enumerated().flatMap { index, minutes -> [WorkoutStep] in
                    let work = WorkoutStep.time(.run, minutes: Double(minutes))
                    return index < 4 ? [work, .time(.recover, minutes: 1)] : [work]
                } + [cooldown]),
    ]
}
