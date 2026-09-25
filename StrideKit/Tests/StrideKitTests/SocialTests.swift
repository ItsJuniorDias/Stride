import Foundation
import Testing
@testable import StrideKit

@Suite struct SocialTests {
    private let utc = TimeZone(identifier: "UTC")!

    private func date(_ month: Int, _ day: Int, _ hour: Int = 8) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))!
    }

    private func card(_ code: String, _ name: String, week: String = "2026-W39", km: Double, month: String = "2026-09",
                      monthKm: Double = 0, cheered: [String] = []) -> RunnerCard {
        RunnerCard(code: code, name: name,
                   stats: RunnerStats(weekKey: week, weekDistance: km * 1_000, weekRuns: 2, monthKey: month, monthDistance: monthKm * 1_000),
                   cheered: cheered, cheerWeekKey: "2026-W39")
    }

    @Test func isoWeeksAndMonths() {
        #expect(RunnerStats.weekKey(for: date(9, 24), timeZone: utc) == "2026-W39")
        // Sunday still belongs to the week that started on Monday.
        #expect(RunnerStats.weekKey(for: date(9, 27, 20), timeZone: utc) == "2026-W39")
        #expect(RunnerStats.weekKey(for: date(9, 28), timeZone: utc) == "2026-W40")
        #expect(RunnerStats.monthKey(for: date(9, 30), timeZone: utc) == "2026-09")
    }

    @Test func statsFromRuns() {
        let samples = [RunSample(date: date(9, 21), distance: 5_000, duration: 1_500),
                       RunSample(date: date(9, 24), distance: 8_000, duration: 2_600),
                       RunSample(date: date(9, 2), distance: 10_000, duration: 3_300),
                       RunSample(date: date(8, 30), distance: 12_000, duration: 4_000)]
        let stats = RunnerStats.compute(from: samples, now: date(9, 25), timeZone: utc)
        #expect(stats.weekDistance == 13_000)
        #expect(stats.weekRuns == 2)
        #expect(stats.monthDistance == 23_000)
        #expect(stats.lastRunDistance == 8_000)
        #expect(stats.streakWeeks == 1)
    }

    @Test func leaderboardRanksAndIgnoresOldWeeks() {
        let me = card("MEMEMEME", "Me", km: 20, cheered: [])
        let ana = card("ANAANAAN", "Ana", km: 25, cheered: [CheerToken.make(for: "MEMEMEME", from: "ANAANAAN")])
        let bia = card("BIABIABI", "Bia", km: 20)
        let old = card("OLDOLDOL", "Caio", week: "2026-W37", km: 40)
        let rows = Leaderboard.rows(me: me, friends: [bia, ana, old], period: .week, now: date(9, 25), timeZone: utc)
        #expect(rows.map(\.name) == ["Ana", "Bia", "Me", "Caio"])
        #expect(rows.map(\.rank) == [1, 2, 2, 4])
        #expect(rows[3].distance == 0)
        #expect(rows.first?.cheeredMe == true)
        #expect(rows.first { $0.isMe }?.code == "MEMEMEME")
    }

    @Test func cheerTokensDontRevealCodes() {
        let token = CheerToken.make(for: "MEMEMEME", from: "ANAANAAN")
        #expect(token.count == 16)
        #expect(!token.contains("MEMEMEME"))
        #expect(token == CheerToken.make(for: "MEMEMEME", from: "ANAANAAN"))
        #expect(token != CheerToken.make(for: "MEMEMEME", from: "BIABIABI"))
    }

    @Test func friendCodes() {
        let code = ShareCode.generate()
        #expect(code.count == 8)
        #expect(ShareCode.normalize(code.lowercased()) == code)
        #expect(ShareCode.normalize("abcd-efgh") == "ABCDEFGH")
        #expect(ShareCode.normalize("Add me on Stride: stride://friend/ABCDEFGH") == "ABCDEFGH")
        #expect(ShareCode.normalize("ABCD-EFG0") == nil)
        #expect(ShareCode.display("ABCDEFGH") == "ABCD-EFGH")
        #expect(StrideLink.friendCode(in: StrideLink.invite(code: "ABCDEFGH")) == "ABCDEFGH")
    }
}
