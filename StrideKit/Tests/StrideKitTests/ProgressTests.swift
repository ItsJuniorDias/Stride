import Foundation
import Testing
import CoreLocation
@testable import StrideKit

/// A fixed Gregorian calendar (Monday weeks, UTC), so the tests don't depend on the machine.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}()

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 8) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
}

private func sample(_ date: Date, km: Double = 5, minutes: Double = 30, climb: Double = 0) -> RunSample {
    RunSample(date: date, distance: km * 1_000, duration: minutes * 60, elevationGain: climb)
}

/// A straight route north with one point per second: `stretches` of (meters, seconds per km).
private func route(_ stretches: [(meters: Double, pace: Double)], segmentBreakAfter: Int? = nil, gap: TimeInterval = 0) -> [RoutePoint] {
    // What CoreLocation measures for one degree of latitude at the equator.
    let metersPerDegree = CLLocation(latitude: 0, longitude: 0).distance(from: CLLocation(latitude: 1, longitude: 0))
    var points = [RoutePoint(latitude: 0, longitude: 0, altitude: 0, timestamp: Date(timeIntervalSince1970: 0))]
    var covered = 0.0, time = 0.0, segment = 0
    for (index, stretch) in stretches.enumerated() {
        let speed = 1_000 / stretch.pace
        var left = stretch.meters
        while left > 1e-9 {
            let step = min(speed, left)
            covered += step
            time += step / speed
            left -= step
            points.append(RoutePoint(latitude: covered / metersPerDegree, longitude: 0, altitude: 0,
                                     timestamp: Date(timeIntervalSince1970: time), segment: segment))
        }
        if index == segmentBreakAfter {
            segment += 1
            time += gap
            points.append(RoutePoint(latitude: covered / metersPerDegree, longitude: 0, altitude: 0,
                                     timestamp: Date(timeIntervalSince1970: time), segment: segment))
        }
    }
    return points
}

@Suite struct RunStatsTests {
    @Test func weekHasSevenDailyBars() {
        let now = date(2026, 9, 24)
        let week = RunStats.interval(of: .week, containing: now, calendar: calendar)
        #expect(week.start == date(2026, 9, 21, 0))
        let bars = RunStats.buckets(of: [sample(date(2026, 9, 22)), sample(date(2026, 9, 22, 18), km: 3)],
                                    period: .week, in: week, calendar: calendar)
        #expect(bars.count == 7)
        #expect(bars[1].totals.runs == 2)
        #expect(bars[1].totals.distance == 8_000)
    }

    @Test func yearHasTwelveMonthlyBarsAndMonthHasItsDays() {
        let year = RunStats.interval(of: .year, containing: date(2026, 5, 1), calendar: calendar)
        #expect(RunStats.buckets(of: [], period: .year, in: year, calendar: calendar).count == 12)
        let february = RunStats.interval(of: .month, containing: date(2026, 2, 10), calendar: calendar)
        #expect(RunStats.buckets(of: [], period: .month, in: february, calendar: calendar).count == 28)
    }

    @Test func periodsAreHalfOpen() {
        let week = RunStats.interval(of: .week, containing: date(2026, 9, 24), calendar: calendar)
        let atNextMonday = sample(week.end)
        #expect(RunStats.totals(of: [atNextMonday], in: week).runs == 0)
        #expect(RunStats.totals(of: [sample(week.start)], in: week).runs == 1)
    }

    @Test func allTimeStartsWithTheFirstRunsYear() {
        let all = RunStats.interval(of: .all, containing: date(2026, 9, 24), firstRun: date(2024, 6, 1), calendar: calendar)
        #expect(all.start == date(2024, 1, 1, 0))
        #expect(RunStats.buckets(of: [], period: .all, in: all, calendar: calendar).count == 3)
    }

    @Test func periodInProgressComparesWithTheSamePointBefore() {
        let now = date(2026, 9, 10, 12)
        let month = RunStats.interval(of: .month, containing: now, calendar: calendar)
        let previous = RunStats.previousInterval(of: .month, before: month, now: now, calendar: calendar)
        #expect(previous?.start == date(2026, 8, 1, 0))
        #expect(previous?.end == date(2026, 8, 10, 12))
        let finished = RunStats.interval(of: .month, containing: date(2026, 7, 5), calendar: calendar)
        let beforeFinished = RunStats.previousInterval(of: .month, before: finished, now: now, calendar: calendar)
        #expect(beforeFinished?.end == finished.start)
        #expect(RunStats.previousInterval(of: .all, before: month, now: now, calendar: calendar) == nil)
    }
}

@Suite struct StreakTests {
    @Test func weekStreakSurvivesAWeekWithNoRunYet() {
        // Runs in the three weeks before this one; none yet this week.
        let dates = [date(2026, 9, 1), date(2026, 9, 9), date(2026, 9, 17)]
        let streaks = Streaks.summary(of: dates, now: date(2026, 9, 22), calendar: calendar)
        #expect(streaks.currentWeeks == 3)
        #expect(streaks.longestWeeks == 3)
    }

    @Test func missedWeekBreaksTheStreak() {
        let dates = [date(2026, 8, 3), date(2026, 8, 10), date(2026, 8, 17), date(2026, 9, 14)]
        let streaks = Streaks.summary(of: dates, now: date(2026, 9, 24), calendar: calendar)
        #expect(streaks.currentWeeks == 1)
        #expect(streaks.longestWeeks == 3)
    }

    @Test func dayStreakSurvivesADaylightSavingMidnight() {
        // Chile skips 00:00–01:00 on Sep 6, 2026.
        var chile = Calendar(identifier: .gregorian)
        chile.timeZone = TimeZone(identifier: "America/Santiago")!
        let dates = [5, 6, 7].map { chile.date(from: DateComponents(year: 2026, month: 9, day: $0, hour: 8))! }
        let streaks = Streaks.summary(of: dates, now: dates[2].addingTimeInterval(3_600), calendar: chile)
        #expect(streaks.currentDays == 3)
        let month = RunStats.interval(of: .month, containing: dates[0], calendar: chile)
        let bars = RunStats.buckets(of: [], period: .month, in: month, calendar: chile)
        #expect(bars.count == 30)
        #expect(bars[10].start == chile.startOfDay(for: bars[10].start))
    }

    @Test func dayStreakCountsYesterdayAndIgnoresDoubles() {
        let dates = [date(2026, 9, 20), date(2026, 9, 21), date(2026, 9, 21, 19), date(2026, 9, 22)]
        let streaks = Streaks.summary(of: dates, now: date(2026, 9, 23, 7), calendar: calendar)
        #expect(streaks.currentDays == 3)
        #expect(streaks.longestDays == 3)
        let broken = Streaks.summary(of: dates, now: date(2026, 9, 25), calendar: calendar)
        #expect(broken.currentDays == 0)
        #expect(Streaks.summary(of: [], now: date(2026, 9, 25), calendar: calendar) == StreakSummary())
    }
}

@Suite struct BestEffortTests {
    @Test func findsTheFastestStretch() {
        // 2 km at 5'00", 1 km at 4'00", 2 km at 5'00".
        let points = route([(2_000, 300), (1_000, 240), (2_000, 300)])
        let efforts = BestEfforts.fromRoute(points)
        #expect(abs((efforts[.oneK] ?? 0) - 240) < 1)
        #expect(abs((efforts[.fiveK] ?? 0) - 1_440) < 1)
        #expect(efforts[.tenK] == nil)
        // The mile takes the fast kilometer plus 609 m at 5'00".
        #expect(abs((efforts[.oneMile] ?? 0) - (240 + 609.344 * 0.3)) < 1)
    }

    @Test func pausesDontCount() {
        // A 10-minute pause in the middle of an even 3 km at 5'00". Every mile spans the pause.
        let points = route([(1_500, 300), (1_500, 300)], segmentBreakAfter: 0, gap: 600)
        let efforts = BestEfforts.fromRoute(points)
        #expect(abs((efforts[.oneK] ?? 0) - 300) < 1)
        #expect(abs((efforts[.oneMile] ?? 0) - 1_609.344 * 0.3) < 1)
    }

    @Test func gpsJumpIsNotARecord() {
        var points = route([(1_500, 300)])
        // A fix 2 km away one second later.
        let last = points[points.count - 1]
        points.append(RoutePoint(latitude: last.latitude + 2_000 / 110_574, longitude: 0, altitude: 0,
                                 timestamp: last.timestamp.addingTimeInterval(1)))
        // The only 1K windows are the honest one (5'00") and ones holding the jump, which are thrown out.
        #expect(abs((BestEfforts.fromRoute(points)[.oneK] ?? 0) - 300) < 1)
    }

    @Test func lateGPSLockDoesntSpeedUpTheRoute() {
        // Apple Watch: 5 km in 25:00 at an even 5'00", but GPS locked after 300 m.
        let points = route([(4_700, 300)])
        let efforts = BestEfforts.compute(route: points, distance: 5_000, duration: 1_500)
        #expect(abs((efforts[.oneK] ?? 0) - 300) < 1)
        #expect(abs((efforts[.fiveK] ?? 0) - 1_500) < 1)
    }

    @Test func iPhoneRouteIsNeverShrunk() {
        // The clock ran 10 s longer than the route (waiting for the first fix): efforts keep the route's pace.
        let efforts = BestEfforts.compute(route: route([(5_000, 298)]), distance: 5_000, duration: 1_500)
        #expect(abs((efforts[.oneK] ?? 0) - 298) < 1)
        #expect(abs((efforts[.fiveK] ?? 0) - 1_490) < 1)
    }

    @Test func onlyTypedDistancesGetTheLooseTolerance() {
        // An Apple Watch run without GPS measured 9,976 m: not a 10K. Typed by hand as 6.2 mi, it is.
        #expect(BestEfforts.compute(route: [], distance: 9_976, duration: 3_000)[.tenK] == nil)
        #expect(BestEfforts.compute(route: [], distance: 9_976, duration: 3_000, typed: true)[.tenK] != nil)
    }

    @Test func missingStretchFallsBackToTheAveragePace() {
        // A 10 km run whose route only covers 4 km.
        let efforts = BestEfforts.compute(route: route([(4_000, 300)]), distance: 10_000, duration: 3_000)
        #expect(abs((efforts[.oneK] ?? 0) - 300) < 1)
        #expect(efforts[.fiveK] == 1_500)
        #expect(efforts[.tenK] == 3_000)
    }

    @Test func runThatReadsAsTheDistanceCounts() {
        // Stopped at "5.00 km" with 4,996 m on the clock, even 5'00" pace.
        let efforts = BestEfforts.fromRoute(route([(4_996, 300)]))
        #expect(abs((efforts[.fiveK] ?? 0) - 1_500) < 1)
        // 4,990 m doesn't read as 5 km.
        #expect(BestEfforts.fromRoute(route([(4_990, 300)]))[.fiveK] == nil)
    }

    @Test func racesTypedInMilesCount() {
        // A marathon logged as 26.2 mi and a 5K as 3.1 mi.
        #expect(BestEfforts.estimated(distance: 26.2 * 1_609.344, duration: 4 * 3_600)[.marathon] != nil)
        #expect(BestEfforts.estimated(distance: 3.1 * 1_609.344, duration: 1_500)[.fiveK] != nil)
        #expect(BestEfforts.estimated(distance: 3 * 1_609.344, duration: 1_500)[.fiveK] == nil)
    }

    @Test func worldRecordPaceIsTheLimit() {
        // 2'24"/km is within reach of an elite runner and is kept; 2'00"/km (30 km/h) is a bike.
        #expect(BestEfforts.fromRoute(route([(1_200, 144)]))[.oneK] != nil)
        #expect(BestEfforts.fromRoute(route([(1_200, 120)]))[.oneK] == nil)
    }

    @Test func manualRunsUseTheirAveragePace() {
        let efforts = BestEfforts.estimated(distance: 10_000, duration: 3_000)
        #expect(efforts[.fiveK] == 1_500)
        #expect(efforts[.tenK] == 3_000)
        #expect(efforts[.half] == nil)
        #expect(BestEfforts.estimated(distance: 10_000, duration: 600).isEmpty)
    }

    @Test func routeIsStretchedToTheRunsDistance() {
        // GPS measured 4.9 km in the run's full time; the run (Apple Watch) says 5 km.
        let points = route([(4_900, 300)])
        let efforts = BestEfforts.compute(route: points, distance: 5_000, duration: 1_470)
        #expect(abs((efforts[.fiveK] ?? 0) - 1_470) < 1)
    }
}

@Suite struct PersonalRecordTests {
    private func entry(_ day: Int, km: Double, fiveK: TimeInterval? = nil, climb: Double = 0) -> RecordEntry {
        var efforts: [EffortDistance: TimeInterval] = [:]
        if let fiveK { efforts[.fiveK] = fiveK }
        return RecordEntry(id: UUID(), date: date(2026, 9, day), distance: km * 1_000, duration: km * 330,
                           elevationGain: climb, efforts: efforts)
    }

    @Test func fastestTimeAndTiesGoToTheEarlierRun() {
        let first = entry(1, km: 5, fiveK: 1_500)
        let second = entry(8, km: 5, fiveK: 1_500)
        let faster = entry(15, km: 6, fiveK: 1_450)
        #expect(PersonalRecords.best(of: [second, first])[.effort(.fiveK)]?.runID == first.id)
        let records = PersonalRecords.best(of: [first, second, faster])
        #expect(records[.effort(.fiveK)]?.runID == faster.id)
        #expect(records[.longestDistance]?.runID == faster.id)
        #expect(records[.mostElevation] == nil)
    }

    @Test func achievementsCompareWithEarlierRunsOnly() {
        let earlier = entry(1, km: 8, fiveK: 1_500)
        let later = entry(20, km: 12, fiveK: 1_400)
        let run = entry(10, km: 10, fiveK: 1_480)
        let kinds = PersonalRecords.achievements(of: run, previous: [earlier, later]).map(\.kind)
        #expect(kinds.contains(.effort(.fiveK)))
        #expect(kinds.contains(.longestDistance))
        let firstRun = PersonalRecords.achievements(of: entry(2, km: 5, fiveK: 1_600), previous: [])
        #expect(firstRun.map(\.kind) == [.effort(.fiveK)])
        #expect(firstRun.first?.previous == nil)
    }

    @Test func spokenRecordsNameTheLongestFirst() {
        let line = CoachScript.records([
            RecordAchievement(kind: .effort(.fiveK), value: 1_400, previous: 1_500),
            RecordAchievement(kind: .effort(.tenK), value: 3_000, previous: nil),
            RecordAchievement(kind: .longestDistance, value: 12_000, previous: 11_000),
        ])
        #expect(line == "New personal records: your first 10K and fastest 5K.")
        #expect(CoachScript.records([]) == nil)
    }
}

@Suite struct ChallengeTests {
    private let september = DateInterval(start: date(2026, 9, 1, 0), end: date(2026, 10, 1, 0))

    @Test func distanceChallengeCompletesOnTheRunThatReachesIt() {
        let samples = [sample(date(2026, 8, 31), km: 50), sample(date(2026, 9, 3), km: 40),
                       sample(date(2026, 9, 12), km: 30), sample(date(2026, 9, 20), km: 30)]
        let status = ChallengeStatus.evaluate(metric: .distance, target: 60_000, interval: september, samples: samples,
                                              now: date(2026, 9, 24), calendar: calendar)
        #expect(status.value == 100_000)
        #expect(status.completedOn == date(2026, 9, 12))
        #expect(status.state == .completed)
        #expect(status.fraction == 1)
    }

    @Test func activeDaysCountDistinctDays() {
        let samples = [sample(date(2026, 9, 3)), sample(date(2026, 9, 3, 19)), sample(date(2026, 9, 5))]
        let status = ChallengeStatus.evaluate(metric: .activeDays, target: 10, interval: september, samples: samples,
                                              now: date(2026, 9, 15, 0), calendar: calendar)
        #expect(status.value == 2)
        #expect(status.state == .active)
        #expect(abs((status.expected ?? 0) - 10 * 14 / 30) < 0.001)
    }

    @Test func unfinishedChallengeIsMissedAfterItEnds() {
        let status = ChallengeStatus.evaluate(metric: .runs, target: 12, interval: september, samples: [sample(date(2026, 9, 3))],
                                              now: date(2026, 10, 2), calendar: calendar)
        #expect(status.state == .missed)
        #expect(status.expected == nil)
    }

    @Test func freshChallengeIsOnTrack() {
        let week = DateInterval(start: date(2026, 9, 24, 0), end: date(2026, 10, 1, 0))
        let status = ChallengeStatus.evaluate(metric: .distance, target: 21_097.5, interval: week, samples: [],
                                              now: date(2026, 9, 24, 20), calendar: calendar)
        #expect(status.expected == 0)
        #expect(ChallengeMetric.runs.behind(value: 2, expected: 2.6, unit: .metric) == nil)
        #expect(ChallengeMetric.runs.behind(value: 2, expected: 3.2, unit: .metric) == "1 run behind")
        #expect(ChallengeMetric.duration.behind(value: 0, expected: 3_600, unit: .metric) == "1 hour behind")
        #expect(ChallengeMetric.runs.progressText(value: 0, target: 1, unit: .metric) == "0 of 1 run")
    }

    @Test func progressNeverRoundsUpToTheTarget() {
        let full = 100.formatted()
        #expect(ChallengeMetric.distance.progressText(value: 99_960, target: 100_000, unit: .metric) == "\(99.9.formatted()) of \(full) km")
        // 3,500 ft survives the round trip through meters.
        let stored = ChallengeMetric.elevation.storedValue(fromDisplay: 3_500, unit: .imperial)
        #expect(ChallengeMetric.elevation.number(stored, unit: .imperial) == 3_500.formatted())
        #expect(ChallengeMetric.elevation.number(stored, unit: .imperial, rounding: .down) == 3_500.formatted())
    }

    @Test func targetsConvertBetweenUnits() {
        #expect(ChallengeMetric.distance.storedValue(fromDisplay: 60, unit: .imperial) == 60 * 1_609.344)
        #expect(ChallengeMetric.duration.displayValue(fromStored: 36_000, unit: .metric) == 10)
        let number = 62.4.formatted(.number.precision(.fractionLength(0...1)))
        #expect(ChallengeMetric.distance.progressText(value: 62_400, target: 100_000, unit: .metric) == "\(number) of 100 km")
        #expect(ChallengeMetric.runs.defaultTitle(target: 12, unit: .metric) == "12 runs")
    }
}
