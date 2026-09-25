import Foundation
import Testing
import SwiftData
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

@Suite struct RouteAnalysisTests {
    /// A straight line north at 1 point per second and `speed` m/s.
    private func line(meters: Double, speed: Double, segment: Int = 0, start: Date = .init(timeIntervalSince1970: 0)) -> [RoutePoint] {
        let count = Int(meters / speed)
        return (0...count).map { i in
            RoutePoint(latitude: Double(i) * speed / 111_195, longitude: 0, altitude: 0,
                       timestamp: start.addingTimeInterval(Double(i)), segment: segment)
        }
    }

    @Test func distanceAndTime() {
        let points = line(meters: 2_000, speed: 4)
        #expect(abs(RouteAnalysis.distance(of: points) - 2_000) < 20)
        #expect(RouteAnalysis.movingTime(of: points) == 500)
    }

    @Test func pausesAreExcluded() {
        let first = line(meters: 1_000, speed: 4)
        let second = line(meters: 1_000, speed: 4, segment: 1, start: .init(timeIntervalSince1970: 10_000))
        #expect(RouteAnalysis.movingTime(of: first + second) == 500)
    }

    @Test func splitsPerKilometer() {
        let splits = RouteAnalysis.splits(from: line(meters: 2_500, speed: 4), unit: .metric)
        #expect(splits.count == 3)
        #expect(abs(splits[0].duration - 250) < 3)
        #expect(splits[2].isPartial(in: .metric))
    }

    @Test func elevationIgnoresNoise() {
        let start = Date(timeIntervalSince1970: 0)
        let altitudes: [Double] = [100, 101, 100, 101, 110, 109, 120, 100]
        let points = altitudes.enumerated().map {
            RoutePoint(latitude: 0, longitude: 0, altitude: $0.element, timestamp: start.addingTimeInterval(Double($0.offset)))
        }
        let result = RouteAnalysis.elevation(of: points)
        #expect(result.gain == 20)
        #expect(result.loss == 20)
    }

    @Test func elevationIgnoresClimbingDuringPauses() {
        let start = Date(timeIntervalSince1970: 0)
        let points = [
            RoutePoint(latitude: 0, longitude: 0, altitude: 100, timestamp: start, segment: 0),
            RoutePoint(latitude: 0, longitude: 0, altitude: 104, timestamp: start.addingTimeInterval(1), segment: 0),
            RoutePoint(latitude: 0, longitude: 0, altitude: 180, timestamp: start.addingTimeInterval(600), segment: 1),
            RoutePoint(latitude: 0, longitude: 0, altitude: 185, timestamp: start.addingTimeInterval(601), segment: 1),
        ]
        #expect(RouteAnalysis.elevation(of: points).gain == 9)
    }
}

@Suite struct ZoneTests {
    @Test func zoneSecondsFromRouteHeartRate() {
        let start = Date(timeIntervalSince1970: 0)
        let rates: [Double] = [100, 150, 150, 185, 185]
        let points = rates.enumerated().map {
            RoutePoint(latitude: 0, longitude: 0, altitude: 0,
                       timestamp: start.addingTimeInterval(Double($0.offset) * 10), heartRate: $0.element)
        }
        let zones = RouteAnalysis.zoneSeconds(of: points, maxHeartRate: 200)
        #expect(zones[.recovery] == 10)
        #expect(zones[.aerobic] == 20)
        #expect(zones[.maximum] == 10)
    }

    @Test func transferRoundTrip() throws {
        let transfer = RunTransfer(startDate: .init(timeIntervalSince1970: 0), duration: 1_800, distance: 5_000,
                                   calories: 350, averageHeartRate: 152, zoneSeconds: [3: 900, 4: 900])
        let decoded = try JSONDecoder().decode(RunTransfer.self, from: JSONEncoder().encode(transfer))
        #expect(decoded.id == transfer.id)
        #expect(decoded.zones[.aerobic] == 900)
    }
}

@Suite struct WatchImportTests {
    @MainActor
    @Test func runFromWatchTransfer() throws {
        let container = try ModelContainer(for: Run.self, Shoe.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let start = Date(timeIntervalSince1970: 0)
        let route = (0...500).map { i in
            RoutePoint(latitude: Double(i) * 4 / 111_195, longitude: 0, altitude: 100,
                       timestamp: start.addingTimeInterval(Double(i)), heartRate: 150)
        }
        let transfer = RunTransfer(startDate: start, duration: 500, distance: 2_000, calories: 140,
                                   averageHeartRate: 150, zoneSeconds: [3: 500], route: route, workoutName: "5 km")
        let run = Run(transfer: transfer)
        container.mainContext.insert(run)

        #expect(run.id == transfer.id)
        #expect(run.source == .watch)
        #expect(run.zoneSeconds[.aerobic] == 500)
        #expect(run.splits.count == 2)
        #expect(run.preview.count > 1)
        #expect(run.title == "5 km")
    }
}

@Suite struct WatchSplitScaleTests {
    @MainActor
    @Test func splitsMatchTheWatchDistance() throws {
        let container = try ModelContainer(for: Run.self, Shoe.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let start = Date(timeIntervalSince1970: 0)
        // GPS says ~1,989 m; the Watch's workout distance says 2,200 m.
        let route = (0...500).map { i in
            RoutePoint(latitude: Double(i) * 4 / 111_195, longitude: 0, altitude: 0, timestamp: start.addingTimeInterval(Double(i)))
        }
        let run = Run(transfer: RunTransfer(startDate: start, duration: 500, distance: 2_200, calories: 150, route: route))
        container.mainContext.insert(run)
        let total = run.splits.reduce(0) { $0 + $1.distance }
        #expect(abs(total - 2_200) < 5)
        #expect(run.splits.count == 3)
    }
}
