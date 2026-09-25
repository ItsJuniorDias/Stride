import Foundation
import SwiftData

/// What a challenge counts.
public enum ChallengeMetric: String, CaseIterable, Codable, Identifiable, Sendable {
    case distance, runs, duration, elevation, activeDays

    public var id: Self { self }

    public var title: String {
        switch self {
        case .distance: "Distance"
        case .runs: "Runs"
        case .duration: "Time"
        case .elevation: "Climbing"
        case .activeDays: "Active days"
        }
    }

    public var symbol: String {
        switch self {
        case .distance: "road.lanes"
        case .runs: "figure.run"
        case .duration: "stopwatch"
        case .elevation: "mountain.2.fill"
        case .activeDays: "calendar"
        }
    }

    /// The unit targets are typed in: km or mi, runs, hours, m or ft, days. Singular for a count of 1.
    public func displayUnit(_ unit: UnitSystem, count: Double? = nil) -> String {
        let one = count == 1
        return switch self {
        case .distance: unit.distanceSymbol
        case .runs: one ? "run" : "runs"
        case .duration: one ? "hour" : "hours"
        case .elevation: unit.elevationSymbol
        case .activeDays: one ? "day" : "days"
        }
    }

    /// A stored value (meters, seconds or a count) in the unit targets are typed in.
    public func displayValue(fromStored value: Double, unit: UnitSystem) -> Double {
        switch self {
        case .distance: value / unit.metersPerUnit
        case .duration: value / 3_600
        case .elevation: unit.elevation(fromMeters: value)
        case .runs, .activeDays: value
        }
    }

    public func storedValue(fromDisplay value: Double, unit: UnitSystem) -> Double {
        switch self {
        case .distance: value * unit.metersPerUnit
        case .duration: value * 3_600
        case .elevation: value / unit.elevation(fromMeters: 1)
        case .runs, .activeDays: value.rounded()
        }
    }

    /// Singular for 1 ("1 run"), for titles and counts.
    func count(_ amount: String, _ value: Double, singular: String, plural: String) -> String {
        "\(amount) \(value == 1 ? singular : plural)"
    }

    /// Decimal places shown: tenths of a kilometer or hour, whole runs, days and meters.
    var fractionDigits: Int {
        switch self {
        case .distance, .duration: 1
        case .elevation, .runs, .activeDays: 0
        }
    }

    /// A value in the display unit, rounded to what's shown. Progress rounds down (99.96 km of 100
    /// isn't "100 of 100"); targets round to the nearest (3,500 ft stays 3,500).
    public func shownValue(_ value: Double, unit: UnitSystem, rounding rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> Double {
        let factor = pow(10, Double(fractionDigits))
        // A hair of slack, so a value stored as 2,999.9999 ft still rounds down to 3,000.
        let display = displayValue(fromStored: value, unit: unit) * factor
        return (rule == .down ? display + 1e-6 : display).rounded(rule) / factor
    }

    /// A value as a number without its unit: "62.4", "12", "7.5", "1,000".
    public func number(_ value: Double, unit: UnitSystem, rounding rule: FloatingPointRoundingRule = .toNearestOrAwayFromZero) -> String {
        shownValue(value, unit: unit, rounding: rule).formatted(.number.precision(.fractionLength(0...fractionDigits)))
    }

    /// The unit after a shown target: "of 1 run", "of 12 runs".
    public func targetUnit(_ target: Double, unit: UnitSystem) -> String {
        displayUnit(unit, count: shownValue(target, unit: unit))
    }

    /// "62.4 of 100 km", "5 of 12 runs".
    public func progressText(value: Double, target: Double, unit: UnitSystem) -> String {
        "\(number(value, unit: unit, rounding: .down)) of \(number(target, unit: unit)) \(targetUnit(target, unit: unit))"
    }

    /// "1.5 km behind", "1 run behind"; nil when on track, including a gap too small to show.
    public func behind(value: Double, expected: Double, unit: UnitSystem) -> String? {
        let gap = expected - value
        guard gap > 0 else { return nil }
        let shown = shownValue(gap, unit: unit, rounding: .down)
        guard shown > 0 else { return nil }
        return "\(number(gap, unit: unit, rounding: .down)) \(displayUnit(unit, count: shown)) behind"
    }

    /// A name for a custom challenge: "Run 50 km", "12 runs", "Climb 500 m".
    public func defaultTitle(target: Double, unit: UnitSystem) -> String {
        let amount = number(target, unit: unit)
        let value = displayValue(fromStored: target, unit: unit)
        return switch self {
        case .distance: "Run \(amount) \(unit.distanceSymbol)"
        case .runs: count(amount, value, singular: "run", plural: "runs")
        case .duration: "\(count(amount, value, singular: "hour", plural: "hours")) of running"
        case .elevation: "Climb \(amount) \(unit.elevationSymbol)"
        case .activeDays: count(amount, value, singular: "active day", plural: "active days")
        }
    }

    func amount(of sample: RunSample) -> Double {
        switch self {
        case .distance: sample.distance
        case .runs: 1
        case .duration: sample.duration
        case .elevation: sample.elevationGain
        case .activeDays: 0
        }
    }
}

/// Where a challenge stands.
public struct ChallengeStatus: Hashable, Sendable {
    public enum State: Hashable, Sendable {
        case upcoming, active, completed, missed
    }

    /// Progress in stored units.
    public let value: Double
    public let target: Double
    /// When the run that reached the target started.
    public let completedOn: Date?
    public let state: State
    /// Where an even effort would be by now, while the challenge is active.
    public let expected: Double?

    /// 0…1.
    public var fraction: Double {
        target > 0 ? min(max(value / target, 0), 1) : 0
    }

    /// The running total after each run, in date order (distinct days for active days).
    public static func progression(metric: ChallengeMetric, samples: [RunSample],
                                   calendar: Calendar = .current) -> [(date: Date, value: Double)] {
        var value = 0.0
        var days = Set<Date>()
        return samples.sorted { $0.date < $1.date }.map { sample in
            if metric == .activeDays {
                days.insert(calendar.startOfDay(for: sample.date))
                value = Double(days.count)
            } else {
                value += metric.amount(of: sample)
            }
            return (sample.date, value)
        }
    }

    /// Runs inside `interval` (start included, end excluded) count toward the target, in date order.
    public static func evaluate(metric: ChallengeMetric, target: Double, interval: DateInterval, samples: [RunSample],
                                now: Date, calendar: Calendar = .current) -> ChallengeStatus {
        let counted = samples.filter { interval.containsHalfOpen($0.date) && $0.date <= now }
        let steps = progression(metric: metric, samples: counted, calendar: calendar)
        let value = steps.last?.value ?? 0
        let completedOn = target > 0 ? steps.first { $0.value >= target }?.date : nil

        let state: State = if completedOn != nil {
            .completed
        } else if now >= interval.end {
            .missed
        } else if now < interval.start {
            .upcoming
        } else {
            .active
        }
        // Measured to the start of today, so a challenge started today isn't already behind.
        let expected: Double? = state == .active && interval.duration > 0
            ? target * max(calendar.startOfDay(for: now).timeIntervalSince(interval.start), 0) / interval.duration
            : nil
        return ChallengeStatus(value: value, target: target, completedOn: completedOn, state: state, expected: expected)
    }
}

/// A personal goal over a date range: run 100 km this month, climb 1,000 m in 30 days.
@Model
public final class Challenge {
    public var id: UUID = UUID()
    public var title: String = ""
    public var metricRaw: String = ChallengeMetric.distance.rawValue
    /// Meters for distance and climbing, seconds for time, a count for runs and active days.
    public var target: Double = 0
    public var startDate: Date = Date.now
    /// Exclusive: runs starting at this moment or later don't count.
    public var endDate: Date = Date.now
    public var createdAt: Date = Date.now
    /// The suggested challenge it was started from, if any.
    public var templateID: String?

    public init(title: String, metric: ChallengeMetric, target: Double, interval: DateInterval, templateID: String? = nil) {
        self.title = title
        self.metricRaw = metric.rawValue
        self.target = target
        self.startDate = interval.start
        self.endDate = interval.end
        self.templateID = templateID
    }

    public var metric: ChallengeMetric {
        get { ChallengeMetric(rawValue: metricRaw) ?? .distance }
        set { metricRaw = newValue.rawValue }
    }

    public var interval: DateInterval {
        DateInterval(start: startDate, end: max(endDate, startDate))
    }

    public func status(samples: [RunSample], now: Date = .now, calendar: Calendar = .current) -> ChallengeStatus {
        ChallengeStatus.evaluate(metric: metric, target: target, interval: interval, samples: samples, now: now, calendar: calendar)
    }
}

/// A suggested challenge.
public struct ChallengeTemplate: Identifiable, Sendable {
    public enum Span: Hashable, Sendable {
        case thisWeek, thisMonth
        /// Starting today.
        case days(Int)
        /// From today through the whole of the given day.
        case through(Date)
    }

    public let id: String
    public let title: String
    public let detail: String
    public let metric: ChallengeMetric
    /// Stored units.
    public let target: Double
    public let span: Span

    public func interval(now: Date, calendar: Calendar = .current) -> DateInterval {
        Self.interval(for: span, now: now, calendar: calendar)
    }

    public static func interval(for span: Span, now: Date, calendar: Calendar = .current) -> DateInterval {
        let today = calendar.startOfDay(for: now)
        switch span {
        case .thisWeek:
            return calendar.dateInterval(of: .weekOfYear, for: now) ?? DateInterval(start: today, duration: 7 * 86_400)
        case .thisMonth:
            return calendar.dateInterval(of: .month, for: now) ?? DateInterval(start: today, duration: 30 * 86_400)
        case .days(let count):
            let end = calendar.date(byAdding: .day, value: max(count, 1), to: today).map { calendar.startOfDay(for: $0) }
                ?? today.addingTimeInterval(Double(max(count, 1)) * 86_400)
            return DateInterval(start: today, end: end)
        case .through(let lastDay):
            // Midnight after the last day, normalized: where daylight saving skips midnight, adding a
            // day to a day that starts at 01:00 would end an hour late.
            let last = calendar.startOfDay(for: max(lastDay, now))
            let end = calendar.date(byAdding: .day, value: 1, to: last).map { calendar.startOfDay(for: $0) } ?? last.addingTimeInterval(86_400)
            return DateInterval(start: today, end: end)
        }
    }

    public func makeChallenge(now: Date = .now, calendar: Calendar = .current) -> Challenge {
        Challenge(title: title, metric: metric, target: target, interval: interval(now: now, calendar: calendar), templateID: id)
    }

    /// Suggested challenges, with round numbers in the runner's unit.
    public static func catalog(unit: UnitSystem) -> [ChallengeTemplate] {
        let metric = unit == .metric
        return [
            ChallengeTemplate(id: "monthly-distance", title: metric ? "100 km month" : "60 mile month",
                              detail: metric ? "Run 100 km before the month ends." : "Run 60 miles before the month ends.",
                              metric: .distance, target: metric ? 100_000 : 60 * 1_609.344, span: .thisMonth),
            ChallengeTemplate(id: "monthly-runs", title: "12 runs", detail: "Get out for 12 runs this month.",
                              metric: .runs, target: 12, span: .thisMonth),
            ChallengeTemplate(id: "half-week", title: "Half marathon week",
                              detail: metric ? "Cover 21.1 km in the next 7 days." : "Cover 13.1 miles in the next 7 days.",
                              metric: .distance, target: 21_097.5, span: .days(7)),
            ChallengeTemplate(id: "climb", title: metric ? "Climb 1,000 m" : "Climb 3,000 ft",
                              detail: "Gain the height of a mountain in 30 days.",
                              metric: .elevation, target: metric ? 1_000 : 914.4, span: .days(30)),
            ChallengeTemplate(id: "monthly-time", title: "10 hours", detail: "Spend 10 hours running this month.",
                              metric: .duration, target: 36_000, span: .thisMonth),
            ChallengeTemplate(id: "active-days", title: "15 active days", detail: "Run on 15 different days this month.",
                              metric: .activeDays, target: 15, span: .thisMonth),
        ]
    }
}
