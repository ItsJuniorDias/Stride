import Testing
@testable import StrideKit

@Suite struct RunFormatTests {
    @Test func durationUnderAnHour() {
        #expect(RunFormat.duration(2_911) == "48:31")
        #expect(RunFormat.duration(0) == "0:00")
    }

    @Test func durationOverAnHour() {
        #expect(RunFormat.duration(3_727) == "1:02:07")
    }

    @Test func paceFormatting() {
        #expect(RunFormat.pace(312) == "5'12\"")
        #expect(RunFormat.pace(nil) == "--")
        #expect(RunFormat.pace(.infinity) == "--")
        #expect(RunFormat.pace(-1) == "--")
    }

    @Test func paceSecondsPerKilometerAndMile() {
        #expect(RunFormat.paceSeconds(distance: 5_000, duration: 1_500, unit: .metric) == 300)
        let perMile = RunFormat.paceSeconds(distance: 1_609.344, duration: 480, unit: .imperial)
        #expect(perMile == 480)
        #expect(RunFormat.paceSeconds(distance: 3, duration: 10, unit: .metric) == nil)
    }

    @Test func elevationDeltaIsSigned() {
        #expect(RunFormat.elevationDelta(12.4, unit: .metric) == "+12 m")
        #expect(RunFormat.elevationDelta(-6, unit: .metric) == "−6 m")
        #expect(RunFormat.elevationDelta(0.2, unit: .metric) == "0 m")
    }
}

@Suite struct SplitTests {
    @Test func fastestIgnoresPartialSplits() {
        let splits = [
            Split(index: 1, distance: 1_000, duration: 320),
            Split(index: 2, distance: 1_000, duration: 298),
            Split(index: 3, distance: 400, duration: 100),
        ]
        #expect(Split.fastest(in: splits, unit: .metric)?.index == 2)
    }
}

@Suite struct HeartRateZoneTests {
    @Test func zonesByPercentOfMax() {
        #expect(HeartRateZone.zone(for: 90, maxHeartRate: 200) == nil)
        #expect(HeartRateZone.zone(for: 100, maxHeartRate: 200) == .recovery)
        #expect(HeartRateZone.zone(for: 145, maxHeartRate: 200) == .aerobic)
        #expect(HeartRateZone.zone(for: 185, maxHeartRate: 200) == .maximum)
    }
}
