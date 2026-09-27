import Foundation
import StrideKit

/// How plan screens put sessions and weeks into words, with the runner's own paces when Stride Pro
/// gives them some: "5 × 800 m at 4'45" /km, 2 min recoveries", "25 min at 6'05"–6'30" /km",
/// "Run 10 km · predicted 49:55".
enum PlanText {
    /// "Intervals" from "Week 3 · Intervals": the week is already the heading.
    static func sessionTitle(_ session: Workout) -> String {
        guard let range = session.name.range(of: " · ") else { return session.name }
        let prefix = session.name[..<range.lowerBound]
        return prefix.hasPrefix("Week ") ? String(session.name[range.upperBound...]) : session.name
    }

    /// The last session of the plan: race day, or First 5K's first 5K.
    static func isRaceDay(_ session: Workout, in plan: TrainingPlan) -> Bool {
        plan.sessions.last?.id == session.id
    }

    /// The race a plan ends with, for its predicted time.
    static func race(of plan: TrainingPlan) -> EffortDistance? {
        switch plan.id {
        case "first-5k": .fiveK
        case "10k": .tenK
        case "half": .half
        default: nil
        }
    }

    /// The session in words. With `paces`, easy runs, tempos and intervals say the pace to run them
    /// at; with `raceTime`, race day says the predicted time. `withRecovery` false leaves the
    /// recoveries out, for a line that also gives the length.
    static func detail(_ session: Workout, in plan: TrainingPlan, paces: TrainingPaces?, raceTime: TimeInterval?,
                       unit: UnitSystem, withRecovery: Bool = true) -> String {
        if isRaceDay(session, in: plan), let raceTime {
            return "\(session.detail) · predicted \(RunFormat.duration(raceTime))"
        }
        guard let paces, let intensity = plan.intensity(of: session) else { return session.detail }
        let pace = paces.formatted(intensity, unit: unit)
        if let blueprint = WorkoutBlueprint(steps: session.steps), blueprint.repeats > 1 {
            var text = "\(blueprint.repeats) × \(length(blueprint.work, unit: unit)) at \(pace)"
            if withRecovery, let recovery = blueprint.recovery {
                text += ", \(length(recovery, unit: unit)) recoveries"
            }
            return text
        }
        guard let run = session.steps.first(where: { $0.kind == .run }) else { return session.detail }
        return "\(length(run.goal, unit: unit)) at \(pace)"
    }

    /// A few words per session for a week that's folded away: "25 min easy", "4 × 800 m",
    /// "5.75 km long", "race".
    static func shortLabel(_ session: Workout, in plan: TrainingPlan, unit: UnitSystem) -> String {
        if isRaceDay(session, in: plan) { return "race" }
        if let blueprint = WorkoutBlueprint(steps: session.steps), blueprint.repeats > 1 {
            return "\(blueprint.repeats) × \(length(blueprint.work, unit: unit))"
        }
        guard let run = session.steps.first(where: { $0.kind == .run }) else { return sessionTitle(session).lowercased() }
        let text = length(run.goal, unit: unit)
        switch plan.intensity(of: session) {
        case .threshold: return "\(text) tempo"
        case .easy:
            if case .distance = run.goal { return "\(text) long" }
            return "\(text) easy"
        default: return text
        }
    }

    /// "25 min easy · 4 × 800 m · 5.75 km long", or "3 runs of 8 × 1 min" when a week repeats one session.
    static func weekSummary(_ sessions: [Workout], in plan: TrainingPlan, unit: UnitSystem) -> String {
        var groups: [(label: String, count: Int)] = []
        for label in sessions.map({ shortLabel($0, in: plan, unit: unit) }) {
            if let last = groups.last, last.label == label {
                groups[groups.count - 1].count += 1
            } else {
                groups.append((label, 1))
            }
        }
        return groups.map { $0.count > 1 ? "\($0.count) runs of \($0.label)" : $0.label }.joined(separator: " · ")
    }

    /// "42 min · 7.5 km": roughly how long and how far, from the runner's paces or typical ones.
    static func length(of steps: [WorkoutStep], paces: TrainingPaces?, unit: UnitSystem) -> String {
        let estimate = paces.map { WorkoutEstimate(steps: steps, paces: $0) } ?? WorkoutEstimate(steps: steps)
        let distance = RunFormat.distance(estimate.distance, unit: unit, fractionDigits: 1)
        return "\(minutes(estimate.duration)) · \(distance) \(unit.distanceSymbol)"
    }

    /// "42 min", "1 h 5 min".
    static func minutes(_ seconds: TimeInterval) -> String {
        let total = Int((max(seconds, 0) / 60).rounded())
        return total >= 60 ? "\(total / 60) h \(total % 60) min" : "\(total) min"
    }

    /// A step's length: "10 min", "800 m", "5.75 km", or miles past a mile when the runner uses them.
    static func length(_ goal: WorkoutStep.Goal, unit: UnitSystem) -> String {
        if case .distance(let meters) = goal, unit == .imperial, meters >= 1_000 {
            let miles = meters / unit.metersPerUnit
            return "\(miles.formatted(.number.precision(.fractionLength(0...1)))) mi"
        }
        return WorkoutBlueprint.text(for: goal, unit: unit)
    }

    /// Each week's share of sessions done, for the week segments.
    static func weekFractions(_ plan: TrainingPlan, completed: Set<String>) -> [Double] {
        plan.weeks.map { sessions in
            sessions.isEmpty ? 0 : Double(sessions.filter { completed.contains($0.id) }.count) / Double(sessions.count)
        }
    }
}
