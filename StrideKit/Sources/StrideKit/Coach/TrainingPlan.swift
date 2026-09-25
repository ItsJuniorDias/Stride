import Foundation

/// A multi-week plan: a few sessions a week, each a ``Workout``.
public struct TrainingPlan: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let summary: String
    public let level: String
    /// Sessions per week, in order.
    public let weeks: [[Workout]]

    public var sessions: [Workout] { weeks.flatMap { $0 } }

    public static let catalog: [TrainingPlan] = [firstFiveK, tenK, halfMarathon]

    public static func plan(id: String) -> TrainingPlan? {
        catalog.first { $0.id == id }
    }

    /// The first session not in `completed`, or nil when the plan is done.
    public func nextSession(completed: Set<String>) -> Workout? {
        sessions.first { !completed.contains($0.id) }
    }

    public func progress(completed: Set<String>) -> Double {
        let total = sessions.count
        return total > 0 ? Double(sessions.filter { completed.contains($0.id) }.count) / Double(total) : 0
    }

    // MARK: Plans

    /// Run/walk intervals building to 30 minutes of running, then a 5K.
    public static var firstFiveK: TrainingPlan {
        let runMinutes: [Double] = [1, 2, 3, 5, 8, 10]
        let walkMinutes: [Double] = [2, 2, 2, 2, 2, 1]
        let repeats = [8, 6, 5, 4, 3, 3]
        let weeks = (0..<6).map { week -> [Workout] in
            (0..<3).map { session -> Workout in
                let id = "5k-w\(week + 1)-s\(session + 1)"
                let name = "Week \(week + 1) · Run \(session + 1)"
                if week == 5, session == 2 {
                    return Workout(id: id, name: "Your first 5K", detail: "Warm up, run 5 km, cool down",
                                   steps: [.time(.warmup, minutes: 5), .distance(.run, meters: 5_000), .time(.cooldown, minutes: 5)])
                }
                let run = runMinutes[week].formatted()
                let walk = walkMinutes[week].formatted()
                return .intervals(id: id, name: name,
                                  detail: "\(repeats[week]) × \(run) min run, \(walk) min walk",
                                  warmup: .time(.warmup, minutes: 5), repeats: repeats[week],
                                  work: .time(.run, minutes: runMinutes[week]), rest: .time(.recover, minutes: walkMinutes[week]),
                                  cooldown: .time(.cooldown, minutes: 5))
            }
        }
        return TrainingPlan(id: "first-5k", name: "First 5K", summary: "From run/walk to running 5 km without stopping.",
                            level: "Beginner · 6 weeks · 3 runs a week", weeks: weeks)
    }

    /// Easy runs, 800 m repeats and a growing long run, ending with a 10K.
    public static var tenK: TrainingPlan {
        let weeks = (0..<8).map { week -> [Workout] in
            let easyMinutes = Double(25 + week * 3)
            let repeats = 4 + week / 2
            let longKilometers = min(5 + Double(week) * 0.75, 10)
            let easy = Workout(id: "10k-w\(week + 1)-s1", name: "Week \(week + 1) · Easy run",
                               detail: "\(Int(easyMinutes)) min at a conversational pace",
                               steps: [.time(.run, minutes: easyMinutes)])
            let intervals = Workout.intervals(id: "10k-w\(week + 1)-s2", name: "Week \(week + 1) · Intervals",
                                              detail: "\(repeats) × 800 m, 2 min recoveries",
                                              warmup: .time(.warmup, minutes: 10), repeats: repeats,
                                              work: .distance(.run, meters: 800), rest: .time(.recover, minutes: 2),
                                              cooldown: .time(.cooldown, minutes: 5))
            let isRace = week == 7
            let long = Workout(id: "10k-w\(week + 1)-s3", name: isRace ? "Race day: 10K" : "Week \(week + 1) · Long run",
                               detail: isRace ? "Run 10 km" : "\(longKilometers.formatted(.number.precision(.fractionLength(0...2)))) km easy",
                               steps: [.distance(.run, meters: isRace ? 10_000 : longKilometers * 1_000)])
            return [easy, intervals, long]
        }
        return TrainingPlan(id: "10k", name: "10K", summary: "Build speed and endurance for a strong 10 km.",
                            level: "Intermediate · 8 weeks · 3 runs a week", weeks: weeks)
    }

    /// Easy runs, tempo runs and a long run that grows to the full half marathon.
    public static var halfMarathon: TrainingPlan {
        let weeks = (0..<10).map { week -> [Workout] in
            let easyMinutes = Double(30 + week * 2)
            let tempoMinutes = Double(15 + week * 2)
            let isRace = week == 9
            let longMeters = isRace ? 21_097.5 : min(8 + Double(week) * 1.3, 19) * 1_000
            let easy = Workout(id: "half-w\(week + 1)-s1", name: "Week \(week + 1) · Easy run",
                               detail: "\(Int(easyMinutes)) min easy", steps: [.time(.run, minutes: easyMinutes)])
            let tempo = Workout(id: "half-w\(week + 1)-s2", name: "Week \(week + 1) · Tempo",
                                detail: "\(Int(tempoMinutes)) min comfortably hard",
                                steps: [.time(.warmup, minutes: 10), .time(.run, minutes: tempoMinutes), .time(.cooldown, minutes: 10)])
            let long = Workout(id: "half-w\(week + 1)-s3", name: isRace ? "Race day: Half Marathon" : "Week \(week + 1) · Long run",
                               detail: isRace ? "Run 21.1 km" : "\((longMeters / 1_000).formatted(.number.precision(.fractionLength(0...1)))) km easy",
                               steps: [.distance(.run, meters: longMeters)])
            return [easy, tempo, long]
        }
        return TrainingPlan(id: "half", name: "Half Marathon", summary: "Go the distance: 21.1 km in 10 weeks.",
                            level: "Intermediate · 10 weeks · 3 runs a week", weeks: weeks)
    }
}
