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

@Suite struct MirrorTests {
    private func coords(_ range: Range<Int>) -> [Coordinate] {
        range.map { Coordinate(latitude: Double($0), longitude: 0) }
    }

    @Test func routeMergesOverlappingBatches() {
        var route = MirroredRoute()
        route.merge(coords(0..<3), startingAt: 0)
        route.merge(coords(2..<5), startingAt: 2)
        route.merge(coords(1..<3), startingAt: 1)
        #expect(route.coordinates.map(\.latitude) == [0, 1, 2, 3, 4])
    }

    @Test func routeRejectsGaps() {
        var route = MirroredRoute()
        route.merge(coords(0..<2), startingAt: 0)
        #expect(route.merge(coords(5..<7), startingAt: 5) == false)
        #expect(route.coordinates.count == 2)
    }

    @Test func elapsedExtrapolatesOnlyWhileRunning() {
        let sent = Date(timeIntervalSince1970: 100)
        let running = MirrorSnapshot(sentAt: sent, elapsed: 60, isPaused: false, distance: 0)
        let paused = MirrorSnapshot(sentAt: sent, elapsed: 60, isPaused: true, distance: 0)
        #expect(running.elapsed(at: sent.addingTimeInterval(5)) == 65)
        #expect(paused.elapsed(at: sent.addingTimeInterval(5)) == 60)
    }

    @Test func snapshotStaysSmall() throws {
        let snapshot = MirrorSnapshot(elapsed: 1_800, isPaused: false, distance: 5_000, heartRate: 150,
                                      zoneSeconds: [2: 300, 3: 1_200, 4: 300], coordinates: coords(0..<100))
        #expect(try JSONEncoder().encode(snapshot).count < 10_000)
    }
}

@Suite struct MirrorProtocolTests {
    @Test func truncateKeepsTheSharedPrefix() {
        var route = MirroredRoute()
        route.merge((0..<10).map { Coordinate(latitude: Double($0), longitude: 0) }, startingAt: 0)
        route.truncate(to: 6)
        #expect(route.coordinates.count == 6)
        let merged = route.merge([Coordinate(latitude: 6, longitude: 0)], startingAt: 6)
        #expect(merged)
        #expect(route.coordinates.count == 7)
    }

    @Test func messagesDecodeApart() throws {
        let command = try JSONEncoder().encode(MirrorCommand(goal: MirrorGoal(type: .distance, distance: 5_000, name: "5 km")))
        let request = try JSONEncoder().encode(MirrorRequest(resendFrom: 12))
        #expect((try? JSONDecoder().decode(MirrorRequest.self, from: command)) == nil)
        #expect((try? JSONDecoder().decode(MirrorCommand.self, from: request)) == nil)
        #expect(try JSONDecoder().decode(MirrorCommand.self, from: command).goal.distance == 5_000)
    }
}

@Suite struct SeriesTests {
    /// North at `speed` m/s, one point per second, with a heart rate and a climb.
    private func line(meters: Double, speed: Double) -> [RoutePoint] {
        let start = Date(timeIntervalSince1970: 0)
        return (0...Int(meters / speed)).map { i in
            RoutePoint(latitude: Double(i) * speed / 110_574, longitude: 0, altitude: Double(i) * 0.1,
                       timestamp: start.addingTimeInterval(Double(i)), heartRate: 140)
        }
    }

    @Test func paceSeriesMatchesSpeed() {
        let series = RouteAnalysis.paceSeries(of: line(meters: 1_000, speed: 4), unit: .metric)
        #expect(series.count >= 9)
        #expect(series.allSatisfy { abs($0.value - 250) < 5 })
    }

    @Test func elevationAndHeartRateSeries() {
        let points = line(meters: 500, speed: 5)
        let elevation = RouteAnalysis.elevationSeries(of: points)
        #expect(elevation.first?.value == 0)
        #expect((elevation.last?.value ?? 0) > 9)
        let heartRate = RouteAnalysis.heartRateSeries(of: points)
        #expect(heartRate.allSatisfy { $0.value == 140 })
    }
}

@Suite struct ChartDataTests {
    @Test func stopsDontShowAsSlowPace() {
        let start = Date(timeIntervalSince1970: 0)
        var points: [RoutePoint] = []
        // 500 m at 4 m/s, 90 s standing still, 500 m at 4 m/s, all one segment.
        for i in 0...125 { points.append(RoutePoint(latitude: Double(i) * 4 / 110_574, longitude: 0, altitude: 0, timestamp: start.addingTimeInterval(Double(i)))) }
        let stopEnd = 125 + 90
        for i in 126...stopEnd { points.append(RoutePoint(latitude: 125 * 4 / 110_574, longitude: 0, altitude: 0, timestamp: start.addingTimeInterval(Double(i)))) }
        for i in 1...125 { points.append(RoutePoint(latitude: Double(125 + i) * 4 / 110_574, longitude: 0, altitude: 0, timestamp: start.addingTimeInterval(Double(stopEnd + i)))) }
        let series = RouteAnalysis.paceSeries(of: points, unit: .metric)
        #expect(series.allSatisfy { abs($0.value - 250) < 10 })
    }

    @Test func watchChartsMatchAverageSpeed() async {
        let start = Date(timeIntervalSince1970: 0)
        // Route: 4 m/s. Workout: 5,000 m in 1,250 s = 4 m/s, but the route started late and is shorter.
        let route = (0...1_000).map { i in
            RoutePoint(latitude: Double(i) * 4 / 110_574, longitude: 0, altitude: 0, timestamp: start.addingTimeInterval(Double(i)))
        }
        let data = await RouteAnalysis.chartData(routeData: nil, decodedRoute: route, distance: 5_000, duration: 1_250,
                                                 source: .watch, unit: .metric)
        #expect(data.pace.allSatisfy { abs($0.value - 250) < 5 })
    }

    @Test func timeOfDayTitles() {
        let calendar = Calendar.current
        let morning = calendar.date(bySettingHour: 7, minute: 0, second: 0, of: .now)!
        #expect(Run.timeOfDayTitle(for: morning) == "Morning Run")
    }
}

@Suite struct CoachTests {
    @Test func cursorWalksThroughSteps() {
        let workout = Workout.intervals(id: "t", name: "Test", detail: "", warmup: .time(.warmup, minutes: 1), repeats: 2,
                                        work: .distance(.run, meters: 400), rest: .time(.recover, seconds: 60), cooldown: nil)
        var cursor = WorkoutCursor(workout: workout)
        #expect(cursor.currentStep?.kind == .warmup)
        #expect(cursor.advance(elapsed: 59, distance: 150).isEmpty)
        #expect(cursor.advance(elapsed: 60, distance: 160) == [.stepStarted(workout.steps[1])])
        #expect(cursor.remaining(elapsed: 100, distance: 360) == .distance(200))
        #expect(cursor.advance(elapsed: 150, distance: 560) == [.stepStarted(workout.steps[2])])
        #expect(cursor.advance(elapsed: 210, distance: 600) == [.stepStarted(workout.steps[3])])
        #expect(cursor.advance(elapsed: 300, distance: 1_000) == [.workoutCompleted])
        #expect(cursor.isFinished)
    }

    @Test func cursorFastForwardsWhenRestored() {
        let workout = IntervalPresets.all[2] // Fartlek: 10 min warm-up + 10 × 30/30 + cool-down
        var cursor = WorkoutCursor(workout: workout)
        // 10 min warm-up, 30 s fast, 30 s easy, then 15 s into the second fast one.
        let events = cursor.advance(elapsed: 675, distance: 3_000)
        #expect(events.count == 3)
        #expect(cursor.currentStep?.kind == .run)
        #expect(cursor.remaining(elapsed: 675, distance: 3_000) == .time(15))
    }

    @Test func paceGuardWaitsAndCoolsDown() {
        var guardian = PaceGuard(target: 330, tolerance: 10, confirmAfter: 20, cooldown: 60, recoverAfter: 5)
        let t0 = Date(timeIntervalSince1970: 0)
        #expect(guardian.evaluate(currentPace: 350, at: t0) == nil)
        #expect(guardian.evaluate(currentPace: 352, at: t0.addingTimeInterval(10)) == nil)
        #expect(guardian.evaluate(currentPace: 352, at: t0.addingTimeInterval(21)) == .tooSlow(22))
        #expect(guardian.evaluate(currentPace: 352, at: t0.addingTimeInterval(50)) == nil)
        // Grazing the edge of the range isn't "back on pace"; clearly inside for 5 s is.
        #expect(guardian.evaluate(currentPace: 339, at: t0.addingTimeInterval(55)) == nil)
        #expect(guardian.evaluate(currentPace: 332, at: t0.addingTimeInterval(56)) == nil)
        #expect(guardian.evaluate(currentPace: 331, at: t0.addingTimeInterval(61)) == .onPace)
        #expect(guardian.evaluate(currentPace: 331, at: t0.addingTimeInterval(62)) == nil)
        #expect(guardian.evaluate(currentPace: nil, at: t0.addingTimeInterval(63)) == nil)
        #expect(guardian.status == nil)
    }

    @Test func savedCursorResumesMixedWorkout() throws {
        // 8 × 400 m: time warm-up, distance reps, time recoveries.
        let workout = IntervalPresets.all[0]
        var cursor = WorkoutCursor(workout: workout)
        _ = cursor.advance(elapsed: 600, distance: 1_500)          // warm-up done
        _ = cursor.advance(elapsed: 700, distance: 1_900)          // rep 1 done
        _ = cursor.advance(elapsed: 790, distance: 2_000)          // recovery 1 done
        let saved = try JSONDecoder().decode(WorkoutCursor.self, from: JSONEncoder().encode(cursor))
        var restored = saved
        _ = restored.advance(elapsed: 820, distance: 2_150)
        #expect(restored.index == cursor.index)
        #expect(restored.currentStep?.kind == .run)
        #expect(workout.runNumber(of: restored.currentStep!) == 2)
    }

    @Test func splitNamesItsLength() {
        let line = CoachScript.split(distance: 4_000, elapsed: 1_320, averagePace: 330, lastSplitPace: 320,
                                     unit: .metric, splitLength: 2, includeTime: false)
        #expect(line.hasSuffix("Last 2 kilometers at 5 minutes 20 seconds per kilometer."))
    }

    @Test func scriptReadsNaturally() {
        #expect(CoachScript.spokenDuration(332) == "5 minutes 32 seconds")
        #expect(CoachScript.spokenDuration(3_660) == "1 hour 1 minute")
        #expect(CoachScript.spokenDistance(2_000, unit: .metric) == "2 kilometers")
        let split = CoachScript.split(distance: 2_000, elapsed: 664, averagePace: 332, lastSplitPace: 330, unit: .metric)
        #expect(split == "2 kilometers. Time 11 minutes 4 seconds. Average pace 5 minutes 32 seconds per kilometer. Last kilometer 5 minutes 30 seconds.")
        let workout = IntervalPresets.all[0]
        #expect(CoachScript.stepStarted(workout.steps[1], in: workout, unit: .metric) == "Interval 1 of 8. Run 400 meters.")
        #expect(CoachScript.pace(.tooSlow(12.4), unit: .metric) == "Speed up. You're 12 seconds per kilometer behind your target.")
    }

    @Test func plansAreWellFormed() {
        for plan in TrainingPlan.catalog {
            let ids = plan.sessions.map(\.id)
            #expect(Set(ids).count == ids.count)
            for session in plan.sessions {
                #expect(!session.steps.isEmpty)
                for step in session.steps {
                    switch step.goal {
                    case .time(let seconds): #expect(seconds > 0)
                    case .distance(let meters): #expect(meters > 0)
                    }
                }
            }
        }
        #expect(TrainingPlan.firstFiveK.sessions.count == 18)
        #expect(TrainingPlan.firstFiveK.nextSession(completed: ["5k-w1-s1"])?.id == "5k-w1-s2")
    }
}
