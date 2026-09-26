import Foundation

/// The distance of the last 7 days against the runner's usual week (acute against chronic load).
/// A sudden jump over the usual is where running injuries come from; a steady climb builds fitness.
public struct TrainingLoad: Hashable, Sendable {
    public enum State: String, CaseIterable, Sendable {
        /// Under 0.8× the usual week: a recovery week, a taper or a break.
        case easing
        /// 0.8–1.1× the usual week.
        case steady
        /// 1.1–1.3× the usual week: how fitness grows.
        case building
        /// Over 1.3× the usual week, with enough weeks behind it to say so.
        case rampTooFast
    }

    /// Meters run in the last 7 days.
    public let acute: Double
    /// Meters per week over the 28 days before the last 7, or over the part of them since the first run.
    public let chronic: Double
    public let state: State

    /// The last 7 days over the usual week: 1 is a usual week.
    public var ratio: Double { acute / chronic }

    /// Above this ratio the load ramps too fast.
    public static let rampLimit = 1.3
    /// Above this ratio the runner is building.
    public static let buildingLimit = 1.1
    /// Under this ratio the runner is easing off.
    public static let easingLimit = 0.8

    static let acuteDays = 7
    static let chronicDays = 28
    /// With less history than this, a single run would make the "usual" week.
    static let minimumHistoryDays = 14.0
    /// A new runner's third week is always a jump over their first two: a ramp is only called too
    /// fast with at least 3 of the 4 usual weeks behind it.
    static let rampHistoryDays = 21.0

    /// The load at `now`. Nil with under two weeks of runs before the last 7 days, or no runs in the
    /// 4 weeks before them.
    public static func compute(samples: [RunSample], now: Date = .now, calendar: Calendar = .current) -> TrainingLoad? {
        guard let first = samples.lazy.map(\.date).min(),
              let acuteStart = calendar.date(byAdding: .day, value: -acuteDays, to: now),
              let chronicStart = calendar.date(byAdding: .day, value: -(acuteDays + chronicDays), to: now)
        else { return nil }
        // The usual week is averaged over the weeks the runner was running, so a new runner's
        // first weeks aren't diluted by the weeks before they started.
        let historyStart = max(chronicStart, calendar.startOfDay(for: first))
        let historyDays = min(acuteStart.timeIntervalSince(historyStart) / 86_400, Double(chronicDays))
        guard historyDays >= minimumHistoryDays else { return nil }

        var acute = 0.0, before = 0.0
        // No upper bound: a run saved after `now` was taken still belongs to the last 7 days.
        for sample in samples where sample.date >= chronicStart {
            if sample.date >= acuteStart { acute += sample.distance } else { before += sample.distance }
        }
        let chronic = before / (historyDays / 7)
        guard chronic > 0 else { return nil }

        let ratio = acute / chronic
        let state: State = if ratio > rampLimit {
            historyDays >= rampHistoryDays ? .rampTooFast : .building
        } else if ratio > buildingLimit {
            .building
        } else if ratio >= easingLimit {
            .steady
        } else {
            .easing
        }
        return TrainingLoad(acute: acute, chronic: chronic, state: state)
    }
}

/// Whether the runner is getting faster: the average pace of each of the last weeks, and a
/// least-squares line through them.
public struct PaceTrend: Hashable, Sendable {
    /// One week with runs.
    public struct Week: Hashable, Sendable, Identifiable {
        /// 0 for the last 7 days, 1 for the 7 before, and so on.
        public let weeksAgo: Int
        /// Where the 7 days start.
        public let start: Date
        /// Seconds per kilometer: the week's time over its distance, so longer runs count for more.
        public let pace: Double

        public var id: Int { weeksAgo }
    }

    /// Weeks with runs, oldest first.
    public let weeks: [Week]
    /// Seconds per kilometer per week; negative is getting faster.
    public let slope: Double
    /// The line's pace for the last 7 days, seconds per kilometer.
    public let current: Double

    /// Weeks from the oldest week in the line to now.
    public var span: Int { weeks.first?.weeksAgo ?? 0 }
    /// How much the line's pace changed over ``span``, seconds per kilometer; negative is faster.
    public var change: Double { slope * Double(span) }

    /// The line's pace `weeksAgo` weeks back, seconds per kilometer.
    public func fitted(weeksAgo: Int) -> Double {
        current - slope * Double(weeksAgo)
    }

    /// Weeks with runs needed for a line worth showing.
    public static let minimumWeeks = 4
    /// How many weeks back the trend looks by default, besides the last 7 days.
    public static let defaultWeeks = 8
    /// Runs shorter than this say little about pace.
    public static let shortestRun = 1_000.0
    /// Paces outside 2'30" to 20'00" per km are GPS trouble, not running.
    static let plausiblePace: ClosedRange<Double> = 150...1_200

    /// The trend over the last 7 days and the `weeksBack` weeks before them, from runs of at least
    /// ``shortestRun``. Nil with runs in fewer than ``minimumWeeks`` of those weeks.
    public static func compute(samples: [RunSample], now: Date = .now, weeksBack: Int = PaceTrend.defaultWeeks,
                               calendar: Calendar = .current) -> PaceTrend? {
        guard weeksBack >= minimumWeeks - 1 else { return nil }
        // Rolling 7-day weeks back from now, newest first, so the last one is never half a week.
        let starts = (1...weeksBack + 1).compactMap { calendar.date(byAdding: .day, value: -7 * $0, to: now) }
        guard starts.count == weeksBack + 1 else { return nil }

        var time = Array(repeating: 0.0, count: starts.count)
        var distance = Array(repeating: 0.0, count: starts.count)
        for sample in samples where sample.distance >= shortestRun && sample.duration > 0 {
            let pace = sample.duration / (sample.distance / 1_000)
            guard plausiblePace.contains(pace), let index = starts.firstIndex(where: { sample.date >= $0 }) else { continue }
            time[index] += sample.duration
            distance[index] += sample.distance
        }

        let weeks = starts.indices.reversed().compactMap { index -> Week? in
            guard distance[index] > 0 else { return nil }
            return Week(weeksAgo: index, start: starts[index], pace: time[index] / (distance[index] / 1_000))
        }
        guard weeks.count >= minimumWeeks else { return nil }

        // x counts weeks toward now, so a falling pace (getting faster) is a negative slope.
        let xs = weeks.map { -Double($0.weeksAgo) }
        let ys = weeks.map(\.pace)
        let meanX = xs.reduce(0, +) / Double(xs.count)
        let meanY = ys.reduce(0, +) / Double(ys.count)
        var sxx = 0.0, sxy = 0.0
        for (x, y) in zip(xs, ys) {
            sxx += (x - meanX) * (x - meanX)
            sxy += (x - meanX) * (y - meanY)
        }
        guard sxx > 0 else { return nil }
        let slope = sxy / sxx
        return PaceTrend(weeks: weeks, slope: slope, current: meanY - slope * meanX)
    }
}
