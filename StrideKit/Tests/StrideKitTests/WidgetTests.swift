import Foundation
import Testing
@testable import StrideKit

@Suite struct WidgetSnapshotTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    private func snapshot(now: Date) -> WidgetSnapshot {
        let samples = [(21, 5_000.0), (23, 8_000), (14, 10_000), (1, 6_000)].map {
            RunSample(date: date($0.0), distance: $0.1, duration: $0.1 * 0.33)
        }
        return WidgetSnapshot(runs: samples, titles: samples.map { _ in "Run" }, weeklyGoal: 20, unit: .metric, now: now, calendar: calendar)
    }

    @Test func weekTotalsAndDays() {
        let now = date(24, 12)
        let snapshot = snapshot(now: now)
        let week = snapshot.week(containing: now, calendar: calendar)
        #expect(week.distance == 13_000)
        #expect(week.runs == 2)
        let days = snapshot.days(ofWeekContaining: now, calendar: calendar)
        #expect(days == [5_000, 0, 8_000, 0, 0, 0, 0])
        #expect(snapshot.lastRun?.date == date(23))
    }

    @Test func keepsOnlyRecentRunsButEveryActiveWeek() {
        let snapshot = snapshot(now: date(24, 12))
        // Every run is within the five weeks kept.
        #expect(snapshot.runs.count == 4)
        #expect(snapshot.activeWeeks.count == 3)
        #expect(snapshot.weekStreak(at: date(24, 12), calendar: calendar) == 2)
    }

    @Test func newWeekStartsFromZero() {
        let snapshot = snapshot(now: date(24, 12))
        #expect(snapshot.week(containing: date(28, 9), calendar: calendar).runs == 0)
    }

    @Test func addingARunOnTheWatch() {
        let snapshot = snapshot(now: date(24, 12))
        let added = snapshot.adding(.init(date: date(25), distance: 4_000, duration: 1_300, title: "Evening Run"), calendar: calendar)
        #expect(added.lastRun?.distance == 4_000)
        #expect(added.week(containing: date(25, 20), calendar: calendar).distance == 17_000)
    }

    @Test func watchRunSurvivesAnOlderPhoneSnapshot() {
        let run = WidgetSnapshot.RunSummary(date: date(25), distance: 4_000, duration: 1_300, title: "Evening Run")
        let older = snapshot(now: date(24, 12))
        // What saveFromPhone does: runs iPhone doesn't have yet are added back, once.
        let merged = [run].reduce(older) { $0.adding($1, calendar: calendar) }
        #expect(merged.runs.count == older.runs.count + 1)
        #expect(merged.adding(run, calendar: calendar).runs.count == merged.runs.count)
    }

    @Test func survivesEncoding() throws {
        let snapshot = snapshot(now: date(24, 12))
        let data = try #require(WidgetStore.encoded(snapshot))
        #expect(WidgetStore.decode(data) == snapshot)
    }

    @Test func deepLinks() {
        #expect(StrideLink(url: StrideLink.run.url) == .run)
        #expect(StrideLink(url: URL(string: "stride://progress")!) == .progress)
        #expect(StrideLink(url: URL(string: "https://example.com/run")!) == nil)
    }
}
