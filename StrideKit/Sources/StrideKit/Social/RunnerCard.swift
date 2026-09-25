import Foundation

/// What a runner shares with friends: this week's and this month's totals, the weekly streak and the
/// last run. Weeks are ISO weeks (Monday to Sunday) so everyone compares the same week.
public struct RunnerStats: Codable, Hashable, Sendable {
    /// "2026-W39".
    public var weekKey: String
    public var weekDistance: Double
    public var weekRuns: Int
    public var weekDuration: TimeInterval
    /// "2026-09".
    public var monthKey: String
    public var monthDistance: Double
    public var monthRuns: Int
    public var streakWeeks: Int
    public var lastRunDate: Date?
    public var lastRunDistance: Double?
    public var lastRunDuration: TimeInterval?

    public init(weekKey: String, weekDistance: Double = 0, weekRuns: Int = 0, weekDuration: TimeInterval = 0,
                monthKey: String, monthDistance: Double = 0, monthRuns: Int = 0, streakWeeks: Int = 0,
                lastRunDate: Date? = nil, lastRunDistance: Double? = nil, lastRunDuration: TimeInterval? = nil) {
        self.weekKey = weekKey
        self.weekDistance = weekDistance
        self.weekRuns = weekRuns
        self.weekDuration = weekDuration
        self.monthKey = monthKey
        self.monthDistance = monthDistance
        self.monthRuns = monthRuns
        self.streakWeeks = streakWeeks
        self.lastRunDate = lastRunDate
        self.lastRunDistance = lastRunDistance
        self.lastRunDuration = lastRunDuration
    }

    /// The ISO week and Gregorian month in the runner's time zone.
    static func calendars(_ timeZone: TimeZone) -> (iso: Calendar, gregorian: Calendar) {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = timeZone
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = timeZone
        return (iso, gregorian)
    }

    public static func weekKey(for date: Date, timeZone: TimeZone = .current) -> String {
        let iso = calendars(timeZone).iso
        let parts = iso.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return String(format: "%04d-W%02d", parts.yearForWeekOfYear ?? 0, parts.weekOfYear ?? 0)
    }

    public static func monthKey(for date: Date, timeZone: TimeZone = .current) -> String {
        let gregorian = calendars(timeZone).gregorian
        let parts = gregorian.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", parts.year ?? 0, parts.month ?? 0)
    }

    /// Totals from every run, as of `now`.
    public static func compute(from samples: [RunSample], now: Date = .now, timeZone: TimeZone = .current) -> RunnerStats {
        let (iso, gregorian) = calendars(timeZone)
        let past = samples.filter { $0.date <= now }
        let week = iso.dateInterval(of: .weekOfYear, for: now).map { interval in past.filter { interval.containsHalfOpen($0.date) } } ?? []
        let month = gregorian.dateInterval(of: .month, for: now).map { interval in past.filter { interval.containsHalfOpen($0.date) } } ?? []
        let last = past.max { $0.date < $1.date }
        return RunnerStats(
            weekKey: weekKey(for: now, timeZone: timeZone),
            weekDistance: week.reduce(0) { $0 + $1.distance },
            weekRuns: week.count,
            weekDuration: week.reduce(0) { $0 + $1.duration },
            monthKey: monthKey(for: now, timeZone: timeZone),
            monthDistance: month.reduce(0) { $0 + $1.distance },
            monthRuns: month.count,
            streakWeeks: Streaks.summary(of: past.map(\.date), now: now, calendar: iso).currentWeeks,
            lastRunDate: last?.date,
            lastRunDistance: last?.distance,
            lastRunDuration: last?.duration
        )
    }
}

/// A runner as friends see them.
public struct RunnerCard: Codable, Hashable, Sendable, Identifiable {
    public var code: String
    public var name: String
    public var stats: RunnerStats
    /// Friends this runner cheered in `cheerWeekKey`, as ``CheerToken``s (never their codes).
    public var cheered: [String]
    public var cheerWeekKey: String
    public var updatedAt: Date?

    public var id: String { code }

    public init(code: String, name: String, stats: RunnerStats, cheered: [String] = [], cheerWeekKey: String = "",
                updatedAt: Date? = nil) {
        self.code = code
        self.name = name
        self.stats = stats
        self.cheered = cheered
        self.cheerWeekKey = cheerWeekKey
        self.updatedAt = updatedAt
    }

    /// Whether this runner cheered the runner with `code` during `weekKey`.
    public func cheers(_ code: String, in weekKey: String) -> Bool {
        cheerWeekKey == weekKey && !cheered.isEmpty && cheered.contains(CheerToken.make(for: code, from: self.code))
    }

    /// One or two letters for an avatar: "Ana Souza" → "AS".
    public var initials: String {
        let letters = name.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }
}

public enum LeaderboardPeriod: String, CaseIterable, Identifiable, Sendable {
    case week, month

    public var id: Self { self }
    public var title: String { self == .week ? "This week" : "This month" }
}

public struct LeaderboardRow: Identifiable, Hashable, Sendable {
    public let code: String
    public let name: String
    public let initials: String
    /// Meters in the period; 0 when the runner hasn't shared anything for it yet.
    public let distance: Double
    public let runs: Int
    public let rank: Int
    public let isMe: Bool
    /// This friend cheered you this week.
    public let cheeredMe: Bool
    public let streakWeeks: Int

    public var id: String { code }
}

public enum Leaderboard {
    /// You and your friends by distance in the period. A card from an earlier week or month counts
    /// as zero (the runner hasn't run, or opened Stride, since). Ties share a rank.
    public static func rows(me: RunnerCard?, friends: [RunnerCard], period: LeaderboardPeriod,
                            now: Date = .now, timeZone: TimeZone = .current) -> [LeaderboardRow] {
        let week = RunnerStats.weekKey(for: now, timeZone: timeZone)
        let month = RunnerStats.monthKey(for: now, timeZone: timeZone)
        let lastWeek = previousWeekKey(week, now: now, timeZone: timeZone)
        let others = friends.filter { $0.code != me?.code }
        let everyone: [RunnerCard] = (me.map { [$0] } ?? []) + others

        struct Entry {
            let card: RunnerCard
            let distance: Double
            let runs: Int
        }
        func entry(_ card: RunnerCard) -> Entry {
            let stats = card.stats
            switch period {
            case .week:
                return stats.weekKey == week ? Entry(card: card, distance: stats.weekDistance, runs: stats.weekRuns) : Entry(card: card, distance: 0, runs: 0)
            case .month:
                return stats.monthKey == month ? Entry(card: card, distance: stats.monthDistance, runs: stats.monthRuns) : Entry(card: card, distance: 0, runs: 0)
            }
        }
        func before(_ a: Entry, _ b: Entry) -> Bool {
            if a.distance != b.distance { return a.distance > b.distance }
            return a.card.name.localizedCaseInsensitiveCompare(b.card.name) == .orderedAscending
        }
        let entries = everyone.map(entry).sorted(by: before)

        var rows: [LeaderboardRow] = []
        for (index, entry) in entries.enumerated() {
            let tied = index > 0 && entries[index - 1].distance == entry.distance
            let rank = tied ? rows[index - 1].rank : index + 1
            let card = entry.card
            let isMe = card.code == me?.code
            let cheeredMe = !isMe && (me.map { card.cheers($0.code, in: week) } ?? false)
            // A streak is alive through this week if the runner ran last week; a card from last week
            // with no run that week means the streak has already broken.
            let streakAlive = card.stats.weekKey == week || (card.stats.weekKey == lastWeek && card.stats.weekRuns > 0)
            rows.append(LeaderboardRow(
                code: card.code, name: card.name, initials: card.initials, distance: entry.distance,
                runs: entry.runs, rank: rank, isMe: isMe, cheeredMe: cheeredMe,
                streakWeeks: streakAlive ? card.stats.streakWeeks : 0
            ))
        }
        return rows
    }

    /// A streak shared last week is still alive until this week ends.
    static func previousWeekKey(_ week: String, now: Date, timeZone: TimeZone) -> String {
        let iso = RunnerStats.calendars(timeZone).iso
        return RunnerStats.weekKey(for: iso.date(byAdding: .weekOfYear, value: -1, to: now) ?? now, timeZone: timeZone)
    }
}

/// Friend codes: 8 characters without look-alikes (no 0/O, 1/I), shown as "ABCD-EFGH".
public enum ShareCode {
    static let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
    public static let length = 8

    public static func generate() -> String {
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }

    /// A code typed or pasted in any form ("abcd efgh", "ABCD-EFGH", or a whole invite), or nil.
    public static func normalize(_ input: String) -> String? {
        let cleaned = input.uppercased().filter { $0.isLetter || $0.isNumber }
        // An invite message holds the code as its last 8 valid characters after "stride://friend/".
        let candidate: String
        if let range = input.range(of: "stride://friend/", options: .caseInsensitive) {
            candidate = String(input[range.upperBound...].uppercased().filter { $0.isLetter || $0.isNumber }.prefix(length))
        } else {
            candidate = cleaned
        }
        guard candidate.count == length, candidate.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return candidate
    }

    public static func display(_ code: String) -> String {
        guard code.count == length else { return code }
        return "\(code.prefix(4))-\(code.suffix(4))"
    }
}
