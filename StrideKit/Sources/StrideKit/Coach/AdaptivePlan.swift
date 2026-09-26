import Foundation

// Plans that adapt to the runner (Stride Pro): personal target paces on quality sessions, and a way
// back in after a break that never changes what's marked done.

public extension TrainingPlan {
    /// The 0-based week a session is in.
    func week(of sessionID: String) -> Int? {
        weeks.firstIndex { weekSessions in weekSessions.contains { $0.id == sessionID } }
    }

    /// What kind of running a session's run steps are, for personal paces. Mirrors the plans above:
    /// 10K and Half Marathon weeks are an easy run, then 800 m intervals (10K) or a tempo (Half), then a
    /// long run, which is easy too. Nil for sessions run by feel: First 5K's run/walk and race days.
    func intensity(of session: Workout) -> TrainingPaces.Intensity? {
        guard let weekIndex = week(of: session.id),
              let index = weeks[weekIndex].firstIndex(where: { $0.id == session.id }) else { return nil }
        let isRaceDay = weekIndex == weeks.count - 1 && index == weeks[weekIndex].count - 1
        guard !isRaceDay else { return nil }
        switch (id, index) {
        case ("10k", 1): return .interval
        case ("half", 1): return .threshold
        case ("10k", _), ("half", _): return .easy
        default: return nil
        }
    }

    /// Whether any session uses personal paces (not First 5K).
    var usesPersonalPaces: Bool {
        sessions.contains { intensity(of: $0) != nil }
    }

    /// The session with the runner's own target pace on its run steps, so the coach's pace alerts hold
    /// them to it. Only tempo and interval sessions get one (see ``TrainingPaces/coachedPace(_:)``); a
    /// step that already has a target keeps it.
    func personalized(_ session: Workout, paces: TrainingPaces) -> Workout {
        guard let intensity = intensity(of: session), let target = paces.coachedPace(intensity) else { return session }
        var workout = session
        workout.steps = session.steps.map { step in
            guard step.kind == .run, step.targetPace == nil else { return step }
            var step = step
            step.targetPace = target
            return step
        }
        return workout
    }

    /// Two weeks without a run: more than a week of the plan was missed.
    static let breakDays = 14

    /// After a break, the week to go through again before carrying on: the last one fully done
    /// (0-based). Nil without a break, while still in the first week, or once the plan is done.
    func suggestedRepeatWeek(completed: Set<String>, lastRunDate: Date?, now: Date = .now,
                             calendar: Calendar = .current) -> Int? {
        guard let next = nextSession(completed: completed), let nextWeek = week(of: next.id), nextWeek > 0,
              let lastRunDate, Self.daysBetween(lastRunDate, and: now, calendar: calendar) >= Self.breakDays
        else { return nil }
        return nextWeek - 1
    }

    /// While repeating: the first session of the repeated weeks not run since the repeat started. Nil
    /// when there's no repeat for this plan, or it's done and the plan carries on as before.
    /// `runSince` holds the session ids of plan runs started at or after ``PlanRepeat/since``.
    func repeatedSession(completed: Set<String>, repeating: PlanRepeat?, runSince: Set<String>) -> Workout? {
        guard let repeating, repeating.planID == id, weeks.indices.contains(repeating.week) else { return nil }
        let all = sessions
        let start = weeks[..<repeating.week].reduce(0) { $0 + $1.count }
        // Up to where the plan was when the repeat started (and never past where it is now), so a
        // session marked done later can't pull a finished repeat back.
        let current = resumeIndex(completed: completed)
        let end = min(current, repeating.resumeIndex)
        guard start < end else { return nil }
        return all[start..<end].first { !runSince.contains($0.id) }
    }

    /// Where the plan is: the index in ``sessions`` of the first session not done, or the count when
    /// every session is done. A repeat records it when it starts.
    func resumeIndex(completed: Set<String>) -> Int {
        nextSession(completed: completed).flatMap { next in sessions.firstIndex { $0.id == next.id } } ?? sessions.count
    }

    /// The session to run next: a repeated one first, then the first one not done.
    func nextSession(completed: Set<String>, repeating: PlanRepeat?, runSince: Set<String>) -> Workout? {
        repeatedSession(completed: completed, repeating: repeating, runSince: runSince) ?? nextSession(completed: completed)
    }

    /// Whole days from one date to another, by the calendar.
    static func daysBetween(_ start: Date, and end: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
}

/// Going through earlier weeks of a plan again after a break. Nothing is marked done or undone:
/// sessions run since ``since`` count toward the repeat, and once the repeated weeks are run, the plan
/// carries on from where it was. Kept on this device only, as a string setting (``rawValue``).
public struct PlanRepeat: Hashable, Sendable {
    public var planID: String
    /// The 0-based week the repeat starts from.
    public var week: Int
    public var since: Date
    /// Where the plan was when the repeat started (``TrainingPlan/resumeIndex(completed:)``): the
    /// repeat ends there, whatever is marked done later.
    public var resumeIndex: Int

    public init(planID: String, week: Int, since: Date, resumeIndex: Int = .max) {
        self.planID = planID
        self.week = week
        self.since = since
        self.resumeIndex = resumeIndex
    }

    /// "10k|1|1758800000|6". Whole seconds, rounded down, so a run started right after still counts.
    public var rawValue: String {
        "\(planID)|\(week)|\(Int(since.timeIntervalSince1970.rounded(.down)))|\(resumeIndex)"
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "|", omittingEmptySubsequences: false)
        guard parts.count == 4, !parts[0].isEmpty, let week = Int(parts[1]), week >= 0,
              let seconds = TimeInterval(parts[2]), let resume = Int(parts[3]), resume >= 0 else { return nil }
        self.init(planID: String(parts[0]), week: week, since: Date(timeIntervalSince1970: seconds), resumeIndex: resume)
    }
}

public extension TrainingPaces {
    /// The pace the coach holds the runner to, seconds per kilometer. Nil for easy running: one pace
    /// give or take 10 s would nag a runner who's rightly going slower, so its range is shown instead.
    func coachedPace(_ intensity: Intensity) -> Double? {
        intensity == .easy ? nil : pace(intensity)
    }

    /// `5'24" /km`, or `6'15"–6'45" /km` for easy running, per the runner's unit.
    func formatted(_ intensity: Intensity, unit: UnitSystem) -> String {
        let bounds = range(intensity)
        let fast = RunFormat.pace(Self.perUnit(bounds.lowerBound, unit: unit))
        let slow = RunFormat.pace(Self.perUnit(bounds.upperBound, unit: unit))
        return "\(fast == slow ? fast : fast + "–" + slow) \(unit.paceSymbol)"
    }
}

public extension TrainingPaces.Intensity {
    /// The pace that suits a repeat of this length: short ones at repetition pace, 2 to 5 minutes (or
    /// up to about a mile) at interval pace, longer ones at tempo.
    static func suited(to goal: WorkoutStep.Goal) -> TrainingPaces.Intensity {
        switch goal {
        case .time(let seconds): seconds <= 90 ? .repetition : seconds <= 330 ? .interval : .threshold
        case .distance(let meters): meters <= 500 ? .repetition : meters <= 1_700 ? .interval : .threshold
        }
    }
}
