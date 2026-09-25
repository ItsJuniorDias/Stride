import Foundation

/// What widgets, complications and Siri need without opening the database: recent runs, the weeks
/// with a run, and the weekly goal. The app writes it to the shared App Group whenever runs or
/// settings change; widgets work out "this week" for the moment they're drawn.
public struct WidgetSnapshot: Codable, Hashable, Sendable {
    public struct RunSummary: Codable, Hashable, Sendable {
        public var date: Date
        /// Meters.
        public var distance: Double
        /// Seconds.
        public var duration: TimeInterval
        public var title: String

        public init(date: Date, distance: Double, duration: TimeInterval, title: String) {
            self.date = date
            self.distance = distance
            self.duration = duration
            self.title = title
        }
    }

    /// Runs from the last few weeks, newest first.
    public var runs: [RunSummary]
    /// One run date from every week with a run, for the weekly streak. Run dates rather than week
    /// starts, so the weeks are worked out in the calendar and time zone the widget is drawn in.
    public var activeWeeks: [Date]
    /// In the runner's unit.
    public var weeklyGoal: Double
    public var unit: UnitSystem
    public var updatedAt: Date
    /// Start dates of Apple Watch runs iPhone has imported recently, deleted or not, so the Watch
    /// knows which of its own runs it no longer needs to count by itself.
    public var importedWatchRuns: [Date]?
    /// The runner's own card and their friends', for the friends leaderboard; nil without friends.
    public var friendCards: [RunnerCard]?
    /// The runner's own friend code, to pick their card out of ``friendCards``.
    public var myCode: String?

    /// This week's leaderboard, as of `date`.
    public func leaderboard(at date: Date = .now) -> [LeaderboardRow] {
        guard let cards = friendCards, !cards.isEmpty else { return [] }
        let me = cards.first { $0.code == myCode }
        return Leaderboard.rows(me: me, friends: cards.filter { $0.code != myCode }, period: .week, now: date)
    }

    public init(runs: [RunSummary], activeWeeks: [Date], weeklyGoal: Double, unit: UnitSystem, updatedAt: Date = .now) {
        self.runs = runs
        self.activeWeeks = activeWeeks
        self.weeklyGoal = weeklyGoal
        self.unit = unit
        self.updatedAt = updatedAt
    }

    /// How many weeks of runs are kept: enough for this week and a few before it.
    public static let weeksKept = 5

    /// A snapshot from every run (any order).
    public init(runs all: [RunSample], titles: [String], weeklyGoal: Double, unit: UnitSystem, now: Date = .now,
                calendar: Calendar = .current) {
        let cutoff = calendar.date(byAdding: .weekOfYear, value: -Self.weeksKept, to: now) ?? now
        let recent = zip(all, titles)
            .filter { $0.0.date >= cutoff }
            .sorted { $0.0.date > $1.0.date }
            .map { RunSummary(date: $0.0.date, distance: $0.0.distance, duration: $0.0.duration, title: $0.1) }
        // The first run of each week (a run date, not the week's start).
        var firstRunOfWeek: [Date: Date] = [:]
        for sample in all {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: sample.date)?.start else { continue }
            firstRunOfWeek[week] = min(firstRunOfWeek[week] ?? sample.date, sample.date)
        }
        self.init(runs: recent, activeWeeks: firstRunOfWeek.values.sorted(), weeklyGoal: weeklyGoal, unit: unit, updatedAt: now)
    }

    /// Distance, time and number of runs in the week containing `date`.
    public func week(containing date: Date, calendar: Calendar = .current) -> (distance: Double, duration: TimeInterval, runs: Int) {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return (0, 0, 0) }
        let inWeek = runs.filter { week.containsHalfOpen($0.date) }
        return (inWeek.reduce(0) { $0 + $1.distance }, inWeek.reduce(0) { $0 + $1.duration }, inWeek.count)
    }

    /// Meters per day of the week containing `date`, starting on the calendar's first weekday.
    public func days(ofWeekContaining date: Date, calendar: Calendar = .current) -> [Double] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return Array(repeating: 0, count: 7) }
        return (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: week.start),
                  let interval = calendar.dateInterval(of: .day, for: day)
            else { return 0 }
            return runs.filter { interval.containsHalfOpen($0.date) }.reduce(0) { $0 + $1.distance }
        }
    }

    /// Weeks in a row with a run, as of `date`.
    public func weekStreak(at date: Date, calendar: Calendar = .current) -> Int {
        Streaks.summary(of: activeWeeks, now: date, calendar: calendar).currentWeeks
    }

    public var lastRun: RunSummary? { runs.first }

    /// The snapshot with a run added, e.g. on Apple Watch right after a workout, before iPhone sends
    /// its own copy.
    public func adding(_ run: RunSummary, calendar: Calendar = .current) -> WidgetSnapshot {
        var copy = self
        guard !runs.contains(where: { abs($0.date.timeIntervalSince(run.date)) < 1 }) else { return self }
        copy.runs = (runs + [run]).sorted { $0.date > $1.date }
        copy.activeWeeks = (activeWeeks + [run.date]).sorted()
        copy.updatedAt = .now
        return copy
    }

    /// Seconds per unit over the week, or nil without distance.
    public func weekPace(containing date: Date, calendar: Calendar = .current) -> Double? {
        let week = week(containing: date, calendar: calendar)
        return RunFormat.paceSeconds(distance: week.distance, duration: week.duration, unit: unit)
    }

    /// An example for widget galleries and previews.
    public static var placeholder: WidgetSnapshot {
        let now = Date.now
        let calendar = Calendar.current
        let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let runs = [(0, 6_200.0, 1_980.0), (2, 8_050, 2_590)].compactMap { day, meters, seconds -> RunSummary? in
            guard let date = calendar.date(byAdding: .day, value: day, to: start)?.addingTimeInterval(7 * 3_600), date <= now else { return nil }
            return RunSummary(date: date, distance: meters, duration: seconds, title: "Morning Run")
        }
        return WidgetSnapshot(runs: runs.reversed(), activeWeeks: [start], weeklyGoal: 20, unit: .metric, updatedAt: now)
    }
}

/// The App Group shared by the app and its widgets (on iPhone, and separately on Apple Watch).
public enum WidgetStore {
    public static let appGroup = "group.alexandrejunior.Stride"
    static let snapshotKey = "widgetSnapshot"
    /// Widget kinds, so the app can ask for a reload.
    public static let weeklyKind = "StrideWeekly"
    public static let quickStartKind = "StrideQuickStart"
    public static let friendsKind = "StrideFriends"
    /// The application-context key the snapshot travels to Apple Watch under.
    public static let contextKey = "widgetSnapshot"

    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    public static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    public static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    static let localRunsKey = "widgetLocalRuns"

    /// Apple Watch: a run recorded here, counted right away and kept until iPhone's snapshot has it.
    public static func addLocalRun(_ run: WidgetSnapshot.RunSummary, unit: UnitSystem) {
        var local = localRuns().filter { $0.date > .now.addingTimeInterval(-7 * 86_400) }
        if !local.contains(where: { abs($0.date.timeIntervalSince(run.date)) < 1 }) { local.append(run) }
        if let data = try? JSONEncoder().encode(local) { defaults?.set(data, forKey: localRunsKey) }
        let snapshot = load() ?? WidgetSnapshot(runs: [], activeWeeks: [], weeklyGoal: 20, unit: unit)
        save(snapshot.adding(run))
    }

    /// Apple Watch: iPhone's snapshot, plus any run recorded here that iPhone hasn't imported yet
    /// (a snapshot sent just before the import would otherwise drop it).
    public static func saveFromPhone(_ snapshot: WidgetSnapshot) {
        let local = localRuns()
        let imported = snapshot.importedWatchRuns ?? []
        let cutoff = Date.now.addingTimeInterval(-7 * 86_400)
        let pending = local.filter { run in
            run.date > cutoff
                && !snapshot.runs.contains { abs($0.date.timeIntervalSince(run.date)) < 1 }
                && !imported.contains { abs($0.timeIntervalSince(run.date)) < 1 }
        }
        if let data = try? JSONEncoder().encode(pending) { defaults?.set(data, forKey: localRunsKey) }
        save(pending.reduce(snapshot) { $0.adding($1) })
    }

    static func localRuns() -> [WidgetSnapshot.RunSummary] {
        guard let data = defaults?.data(forKey: localRunsKey) else { return [] }
        return (try? JSONDecoder().decode([WidgetSnapshot.RunSummary].self, from: data)) ?? []
    }

    /// The snapshot as data, for sending to Apple Watch.
    public static func encoded(_ snapshot: WidgetSnapshot) -> Data? {
        try? JSONEncoder().encode(snapshot)
    }

    public static func decode(_ data: Data) -> WidgetSnapshot? {
        try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
