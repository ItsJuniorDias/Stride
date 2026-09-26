import Foundation
import Testing
@testable import StrideKit

/// A fixed Gregorian calendar (Monday weeks, UTC), so the tests don't depend on the machine.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.firstWeekday = 2
    return calendar
}()

private let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!

private func daysAgo(_ days: Int) -> Date {
    calendar.date(byAdding: .day, value: -days, to: now)!
}

private func entry(_ date: Date, _ efforts: [EffortDistance: TimeInterval]) -> RecordEntry {
    RecordEntry(id: UUID(), date: date, distance: 0, duration: 0, elevationGain: 0, efforts: efforts)
}

/// A run `days` ago of `km` at `pace` seconds per kilometer.
private func run(daysAgo days: Int, km: Double, pace: Double = 330) -> RunSample {
    RunSample(date: daysAgo(days), distance: km * 1_000, duration: km * pace)
}

@Suite struct RacePredictorTests {
    @Test func riegelScalesWithTheExponent() {
        let tenK = RacePredictor.riegel(1_200, from: 5_000, to: 10_000)
        #expect(abs(tenK - 1_200 * pow(2, 1.06)) < 1e-9)
        #expect(RacePredictor.riegel(1_200, from: 5_000, to: 5_000) == 1_200)
    }

    @Test func usesRecentEffortsOverFasterOldOnes() throws {
        let entries = [
            entry(daysAgo(10), [.fiveK: 1_560]),
            entry(daysAgo(20), [.fiveK: 1_500]),
            entry(daysAgo(30), [.fiveK: 1_620]),
            entry(daysAgo(300), [.fiveK: 1_100]),
        ]
        let result = try #require(RacePredictor.predict(from: entries, now: now, calendar: calendar))
        #expect(result.basis == .recent)
        #expect(result[.fiveK]?.time == 1_500)
        #expect(result[.fiveK]?.source == .fiveK)
        #expect(result[.fiveK]?.sourceDate == daysAgo(20))
        #expect(result.fiveKEquivalent == 1_500)
    }

    @Test func fallsBackToTheBestEverOnlyWithoutEnoughRecentRuns() throws {
        let old = [
            entry(daysAgo(200), [.fiveK: 1_300]),
            entry(daysAgo(220), [.fiveK: 1_250]),
            entry(daysAgo(240), [.fiveK: 1_400]),
        ]
        let result = try #require(RacePredictor.predict(from: old + [entry(daysAgo(5), [.fiveK: 1_500])], now: now, calendar: calendar))
        #expect(result.basis == .allTime)
        #expect(result.fiveKEquivalent == 1_250)
    }

    @Test func needsAFewRuns() {
        let entries = [entry(daysAgo(3), [.fiveK: 1_500]), entry(daysAgo(6), [.fiveK: 1_500]), entry(daysAgo(9), [:])]
        #expect(RacePredictor.predict(from: entries, now: now, calendar: calendar) == nil)
    }

    @Test func neverPredictsAMarathonFromUnderFiveK() throws {
        let short: [EffortDistance: TimeInterval] = [.oneK: 270, .oneMile: 450]
        let entries = (1...3).map { entry(daysAgo($0 * 5), short) }
        let result = try #require(RacePredictor.predict(from: entries, now: now, calendar: calendar))
        #expect(result[.marathon] == nil)
        #expect(result[.half] == nil)
        #expect(result[.tenK]?.source == .oneMile)
        #expect(result[.fiveK] != nil)
        #expect(!RacePredictor.canPredict(.marathon, from: .oneMile))
        #expect(RacePredictor.canPredict(.marathon, from: .fiveK))
        #expect(RacePredictor.shortestEffort(for: .marathon) == .fiveK)
        #expect(RacePredictor.shortestEffort(for: .half) == .fiveK)
        #expect(RacePredictor.shortestEffort(for: .tenK) == .oneMile)
    }

    @Test func aNearTieGoesToTheCloserEffort() throws {
        // From the 5K, Riegel says about 41:42 for 10K; the 10K itself was 41:50. Close enough to trust the 10K.
        let entries = [
            entry(daysAgo(4), [.fiveK: 1_200]),
            entry(daysAgo(8), [.tenK: 2_510]),
            entry(daysAgo(12), [.fiveK: 1_300]),
        ]
        let result = try #require(RacePredictor.predict(from: entries, now: now, calendar: calendar))
        #expect(result[.tenK]?.source == .tenK)
        #expect(result[.tenK]?.time == 2_510)
        #expect(result[.fiveK]?.source == .fiveK)
        #expect(result[.fiveK]?.time == 1_200)
    }

    @Test func aClearlyFasterEffortWinsFromFurtherAway() throws {
        let entries = [
            entry(daysAgo(4), [.fiveK: 1_200]),
            entry(daysAgo(8), [.tenK: 2_760]),
            entry(daysAgo(12), [.fiveK: 1_300]),
        ]
        let result = try #require(RacePredictor.predict(from: entries, now: now, calendar: calendar))
        let tenK = try #require(result[.tenK])
        #expect(tenK.source == .fiveK)
        #expect(abs(tenK.time - RacePredictor.riegel(1_200, from: 5_000, to: 10_000)) < 1e-9)
        #expect(result[.marathon] != nil)
        // Slower per kilometer the longer the race.
        let paces = RacePredictor.races.compactMap { result[$0]?.pace(in: .metric) }
        #expect(paces.count == 4)
        #expect(paces == paces.sorted())
    }
}

@Suite struct TrainingPacesTests {
    @Test func pacesFollowTheFiveK() throws {
        let paces = try #require(TrainingPaces(fiveKTime: 1_500))
        #expect(paces.fiveKPace == 300)
        #expect(abs(paces.easy.lowerBound - 375) < 1e-9)
        #expect(abs(paces.easy.upperBound - 405) < 1e-9)
        #expect(abs(paces.threshold - 324) < 1e-9)
        #expect(paces.interval == 300)
        #expect(abs(paces.repetition - 285) < 1e-9)
        #expect(paces.marathon > 335 && paces.marathon < 345)
        #expect(abs(paces.pace(.easy) - 390) < 1e-9)
    }

    @Test func intensitiesGetFaster() throws {
        let paces = try #require(TrainingPaces(fiveKTime: 1_800))
        let order = TrainingPaces.Intensity.allCases.map { paces.range($0).lowerBound }
        #expect(order == order.sorted(by: >))
    }

    @Test func implausibleFiveKHasNoPaces() {
        #expect(TrainingPaces(fiveKTime: 300) == nil)
        #expect(TrainingPaces(fiveKTime: .infinity) == nil)
        #expect(TrainingPaces(fiveKTime: 10_000) == nil)
    }

    @Test func convertsToMiles() {
        #expect(abs(TrainingPaces.perUnit(300, unit: .imperial) - 482.803_2) < 1e-6)
        #expect(TrainingPaces.perUnit(300, unit: .metric) == 300)
    }

    @Test func predictionsCarryPaces() throws {
        let entries = (1...3).map { entry(daysAgo($0 * 7), [.fiveK: 1_500]) }
        let result = try #require(RacePredictor.predict(from: entries, now: now, calendar: calendar))
        #expect(result.trainingPaces?.interval == 300)
    }
}

@Suite struct TrainingLoadTests {
    /// Two runs a week for six weeks: `last` km each in the last 7 days, 10 km each before.
    private func weeks(last: Double) -> [RunSample] {
        (0..<6).flatMap { week in
            [1, 4].map { run(daysAgo: 7 * week + $0, km: week == 0 ? last : 10) }
        }
    }

    @Test func usualWeekIsSteady() throws {
        let load = try #require(TrainingLoad.compute(samples: weeks(last: 10), now: now, calendar: calendar))
        #expect(load.acute == 20_000)
        #expect(abs(load.chronic - 20_000) < 1e-6)
        #expect(abs(load.ratio - 1) < 1e-6)
        #expect(load.state == .steady)
    }

    @Test func statesFollowTheRatio() throws {
        let building = try #require(TrainingLoad.compute(samples: weeks(last: 12), now: now, calendar: calendar))
        #expect(building.state == .building)
        let ramping = try #require(TrainingLoad.compute(samples: weeks(last: 15), now: now, calendar: calendar))
        #expect(ramping.state == .rampTooFast)
        let easing = try #require(TrainingLoad.compute(samples: weeks(last: 5), now: now, calendar: calendar))
        #expect(easing.state == .easing)
    }

    @Test func needsTwoWeeksOfHistory() {
        let samples = [run(daysAgo: 17, km: 5), run(daysAgo: 12, km: 5), run(daysAgo: 3, km: 5)]
        #expect(TrainingLoad.compute(samples: samples, now: now, calendar: calendar) == nil)
        #expect(TrainingLoad.compute(samples: [], now: now, calendar: calendar) == nil)
    }

    @Test func newRunnersJumpIsBuildingNotTooFast() throws {
        let samples = [25, 20, 15, 10].map { run(daysAgo: $0, km: 5) } + [3, 1].map { run(daysAgo: $0, km: 10) }
        let load = try #require(TrainingLoad.compute(samples: samples, now: now, calendar: calendar))
        // The usual week counts only the days since the first run, not all 4 weeks.
        #expect(load.chronic > 20_000 / 4)
        #expect(load.ratio > TrainingLoad.rampLimit)
        #expect(load.state == .building)
    }

    @Test func noRunsInTheUsualWeeksHasNoLoad() {
        let samples = [run(daysAgo: 90, km: 10), run(daysAgo: 2, km: 10)]
        #expect(TrainingLoad.compute(samples: samples, now: now, calendar: calendar) == nil)
    }
}

@Suite struct PaceTrendTests {
    @Test func fasterEveryWeekIsANegativeSlope() throws {
        // 5 s/km faster each week for 9 weeks: 5'40" eight weeks ago, 5'00" now.
        let samples = (0...8).map { run(daysAgo: 7 * $0 + 2, km: 10, pace: 300 + 5 * Double($0)) }
        let trend = try #require(PaceTrend.compute(samples: samples, now: now, calendar: calendar))
        #expect(trend.weeks.count == 9)
        #expect(trend.weeks.first?.weeksAgo == 8)
        #expect(abs(trend.slope + 5) < 1e-9)
        #expect(abs(trend.current - 300) < 1e-9)
        #expect(trend.span == 8)
        #expect(abs(trend.change + 40) < 1e-9)
        #expect(abs(trend.fitted(weeksAgo: 8) - 340) < 1e-9)
    }

    @Test func needsFourWeeksWithRuns() {
        let samples = [2, 9, 16].map { run(daysAgo: $0, km: 8) }
        #expect(PaceTrend.compute(samples: samples, now: now, calendar: calendar) == nil)
        let short = [2, 9, 16, 23].map { run(daysAgo: $0, km: 0.5) }
        #expect(PaceTrend.compute(samples: short, now: now, calendar: calendar) == nil)
    }

    @Test func weekPaceWeighsLongerRunsMore() throws {
        let samples = [run(daysAgo: 1, km: 10, pace: 300), run(daysAgo: 3, km: 5, pace: 360)]
            + [9, 16, 23].map { run(daysAgo: $0, km: 8, pace: 330) }
        let trend = try #require(PaceTrend.compute(samples: samples, now: now, calendar: calendar))
        #expect(abs((trend.weeks.last?.pace ?? 0) - 320) < 1e-9)
        #expect(trend.weeks.last?.weeksAgo == 0)
    }

    @Test func runsOlderThanTheWindowDontCount() {
        let samples = [2, 9, 16].map { run(daysAgo: $0, km: 8) } + [run(daysAgo: 80, km: 8)]
        #expect(PaceTrend.compute(samples: samples, now: now, calendar: calendar) == nil)
    }
}
