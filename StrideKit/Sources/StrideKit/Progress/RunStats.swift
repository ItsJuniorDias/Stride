import Foundation

/// The numbers of one run that stats, streaks, records and challenges need. Plain values, so the
/// math is testable and never touches the database.
public struct RunSample: Hashable, Sendable {
    public var date: Date
    /// Meters.
    public var distance: Double
    /// Moving time in seconds.
    public var duration: TimeInterval
    /// Meters.
    public var elevationGain: Double
    /// Kilocalories.
    public var calories: Double

    public init(date: Date, distance: Double, duration: TimeInterval, elevationGain: Double = 0, calories: Double = 0) {
        self.date = date
        self.distance = distance
        self.duration = duration
        self.elevationGain = elevationGain
        self.calories = calories
    }
}

/// Totals over a set of runs.
public struct RunTotals: Hashable, Sendable {
    public var runs = 0
    public var distance = 0.0
    public var duration: TimeInterval = 0
    public var elevationGain = 0.0
    public var calories = 0.0
    public var longestDistance = 0.0

    public init() {}

    public init(_ samples: some Sequence<RunSample>) {
        for sample in samples { add(sample) }
    }

    public mutating func add(_ sample: RunSample) {
        runs += 1
        distance += sample.distance
        duration += sample.duration
        elevationGain += sample.elevationGain
        calories += sample.calories
        longestDistance = max(longestDistance, sample.distance)
    }

    public func averagePace(in unit: UnitSystem) -> Double? {
        RunFormat.paceSeconds(distance: distance, duration: duration, unit: unit)
    }
}

/// The span the Progress screen summarizes.
public enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week, month, year, all

    public var id: Self { self }

    public var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .year: "Year"
        case .all: "All"
        }
    }

    /// The calendar unit of the period itself; nil for all time.
    public var component: Calendar.Component? {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        case .all: nil
        }
    }

    /// The calendar unit of one chart bar: days in a week or month, months in a year, years overall.
    public var bucketComponent: Calendar.Component {
        switch self {
        case .week, .month: .day
        case .year: .month
        case .all: .year
        }
    }
}

/// One chart bar.
public struct StatsBucket: Identifiable, Hashable, Sendable {
    public let start: Date
    public let end: Date
    public let totals: RunTotals
    public var id: Date { start }
}

public extension DateInterval {
    /// Start included, end excluded: a run at midnight belongs to the day it starts, never to two periods.
    func containsHalfOpen(_ date: Date) -> Bool {
        date >= start && date < end
    }
}

public enum RunStats {
    /// The week, month or year containing `date`. All time runs from the start of the first run's year
    /// to the end of the year containing `date`.
    public static func interval(of period: StatsPeriod, containing date: Date, firstRun: Date? = nil,
                                calendar: Calendar = .current) -> DateInterval {
        let fallback = DateInterval(start: date, duration: 0)
        guard let component = period.component else {
            let end = calendar.dateInterval(of: .year, for: date)?.end ?? date
            let start = calendar.dateInterval(of: .year, for: min(firstRun ?? date, date))?.start ?? date
            return DateInterval(start: start, end: max(end, start))
        }
        return calendar.dateInterval(of: component, for: date) ?? fallback
    }

    /// `date` moved by whole periods. All time doesn't move.
    public static func shifted(_ date: Date, period: StatsPeriod, by value: Int, calendar: Calendar = .current) -> Date {
        guard let component = period.component else { return date }
        return calendar.date(byAdding: component, value: value, to: date) ?? date
    }

    /// The period before `interval`. While the shown period is still in progress it's cut to the same
    /// point, so half a month isn't compared with a whole one.
    public static func previousInterval(of period: StatsPeriod, before interval: DateInterval, now: Date,
                                        calendar: Calendar = .current) -> DateInterval? {
        guard let component = period.component,
              let start = calendar.date(byAdding: component, value: -1, to: interval.start),
              start < interval.start
        else { return nil }
        guard interval.containsHalfOpen(now) else { return DateInterval(start: start, end: interval.start) }
        // The same calendar distance into the previous period (days, then time of day), so daylight
        // saving and month lengths don't shift the point compared.
        let elapsed = calendar.dateComponents([.day, .hour, .minute, .second], from: interval.start, to: now)
        let end = calendar.date(byAdding: elapsed, to: start) ?? start.addingTimeInterval(now.timeIntervalSince(interval.start))
        return DateInterval(start: start, end: min(max(end, start), interval.start))
    }

    public static func totals(of samples: [RunSample], in interval: DateInterval) -> RunTotals {
        RunTotals(samples.lazy.filter { interval.containsHalfOpen($0.date) })
    }

    /// Chart bars covering `interval`: one per day for a week or month, per month for a year, per year overall.
    public static func buckets(of samples: [RunSample], period: StatsPeriod, in interval: DateInterval,
                               calendar: Calendar = .current) -> [StatsBucket] {
        let component = period.bucketComponent
        var starts: [Date] = []
        var cursor = calendar.dateInterval(of: component, for: interval.start)?.start ?? interval.start
        while cursor < interval.end {
            starts.append(cursor)
            // Back to the start of the next bar: where daylight saving skips midnight, adding a day
            // to 00:00 lands at 01:00 and every later bar would start an hour late.
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor),
                  let nextStart = calendar.dateInterval(of: component, for: next)?.start ?? Optional(next),
                  nextStart > cursor
            else { break }
            cursor = nextStart
        }
        guard !starts.isEmpty else { return [] }

        var totals = Array(repeating: RunTotals(), count: starts.count)
        for sample in samples where interval.containsHalfOpen(sample.date) {
            // The last bar starting at or before the run.
            var low = 0, high = starts.count - 1
            while low < high {
                let mid = (low + high + 1) / 2
                if starts[mid] <= sample.date { low = mid } else { high = mid - 1 }
            }
            totals[low].add(sample)
        }
        return starts.indices.map { index in
            let end = index + 1 < starts.count ? starts[index + 1] : interval.end
            return StatsBucket(start: starts[index], end: end, totals: totals[index])
        }
    }

    /// Meters run per day, keyed by the start of the day.
    public static func dailyDistance(of samples: [RunSample], calendar: Calendar = .current) -> [Date: Double] {
        samples.reduce(into: [:]) { result, sample in
            result[calendar.startOfDay(for: sample.date), default: 0] += sample.distance
        }
    }
}
