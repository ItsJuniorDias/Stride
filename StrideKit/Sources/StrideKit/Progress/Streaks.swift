import Foundation

/// Consecutive weeks and days with at least one run.
public struct StreakSummary: Hashable, Sendable {
    public var currentWeeks = 0
    public var longestWeeks = 0
    public var currentDays = 0
    public var longestDays = 0

    public init(currentWeeks: Int = 0, longestWeeks: Int = 0, currentDays: Int = 0, longestDays: Int = 0) {
        self.currentWeeks = currentWeeks
        self.longestWeeks = longestWeeks
        self.currentDays = currentDays
        self.longestDays = longestDays
    }
}

public enum Streaks {
    /// Streaks from run start dates. A current streak is still alive until the week (or day) after its
    /// last run ends: no run yet today doesn't break a daily streak that ran through yesterday.
    public static func summary(of dates: [Date], now: Date = .now, calendar: Calendar = .current) -> StreakSummary {
        // Days are counted by number, not by stepping dates: where daylight saving skips midnight,
        // a day starts at 01:00 and stepping a day from 00:00 would never land on it.
        func dayNumber(_ date: Date) -> Int? { calendar.ordinality(of: .day, in: .era, for: date) }
        func weekNumber(_ date: Date) -> Int? { calendar.dateInterval(of: .weekOfYear, for: date).flatMap { dayNumber($0.start) } }

        let past = dates.filter { $0 <= now }
        let days = Set(past.compactMap(dayNumber))
        let weeks = Set(past.compactMap(weekNumber))
        return StreakSummary(
            currentWeeks: weekNumber(now).map { current(weeks, anchor: $0, step: 7) } ?? 0,
            longestWeeks: longest(weeks, step: 7),
            currentDays: dayNumber(now).map { current(days, anchor: $0, step: 1) } ?? 0,
            longestDays: longest(days, step: 1)
        )
    }

    /// Units in a row ending at `anchor`, or at the unit before it when `anchor` has no run yet.
    private static func current(_ units: Set<Int>, anchor: Int, step: Int) -> Int {
        var cursor = units.contains(anchor) ? anchor : anchor - step
        var count = 0
        while units.contains(cursor) {
            count += 1
            cursor -= step
        }
        return count
    }

    private static func longest(_ units: Set<Int>, step: Int) -> Int {
        var best = 0, run = 0
        var previous: Int?
        for unit in units.sorted() {
            run = previous.map { unit - $0 == step } == true ? run + 1 : 1
            best = max(best, run)
            previous = unit
        }
        return best
    }
}
