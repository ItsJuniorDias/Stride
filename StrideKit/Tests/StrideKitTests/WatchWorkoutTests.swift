import Foundation
import Testing
@testable import StrideKit

@Suite struct WatchWorkoutTests {
    private let workout = IntervalPresets.all[0]

    @Test func goalsFromOlderAppsStillDecode() throws {
        let old = Data(#"{"type":"intervals","name":"8 × 400 m"}"#.utf8)
        let goal = try JSONDecoder().decode(MirrorGoal.self, from: old)
        #expect(goal.type == .intervals)
        #expect(goal.workout == nil)
    }

    @Test func goalCarriesItsWorkout() throws {
        let command = MirrorCommand(goal: MirrorGoal(type: .intervals, name: workout.name, workout: workout))
        let data = try JSONEncoder().encode(command)
        #expect((try? JSONDecoder().decode(MirrorRequest.self, from: data)) == nil)
        #expect(try JSONDecoder().decode(MirrorCommand.self, from: data).goal.workout == workout)
    }

    @Test func libraryRoundTrips() throws {
        let data = try #require(WatchContext.encode(IntervalPresets.all))
        #expect(WatchContext.decodeWorkouts(data) == IntervalPresets.all)
        #expect(WatchContext.decodeWorkouts(Data("{}".utf8)) == nil)
        // Five presets leave plenty of room in the application context.
        #expect(data.count < 10_000)
    }

    @Test func mirroredStepCountsDownBetweenSnapshots() {
        // Step 2 is the first 90 s recovery of 8 × 400 m.
        let progress = MirrorWorkoutProgress(workout: workout, stepIndex: 2, remaining: .time(60))
        #expect(progress.currentStep?.kind == .recover)
        #expect(progress.nextStep?.kind == .run)
        let later = progress.remaining(after: 15)
        #expect(later == .time(45))
        #expect(progress.progress(remaining: later) == 0.5)
        #expect(progress.remaining(after: 120) == .time(0))
    }

    @Test func mirroredDistanceStepWaitsForTheNextSnapshot() {
        let progress = MirrorWorkoutProgress(workout: workout, stepIndex: 1, remaining: .distance(100))
        #expect(progress.remaining(after: 30) == .distance(100))
        #expect(progress.progress(remaining: .distance(100)) == 0.75)
    }

    @Test func finishedWorkoutHasNoStep() {
        let progress = MirrorWorkoutProgress(workout: workout, stepIndex: workout.steps.count, remaining: nil)
        #expect(progress.isFinished)
        #expect(progress.currentStep == nil)
        #expect(progress.progress(remaining: nil) == 1)
    }

    @Test func snapshotWithWorkoutStaysSmall() throws {
        let coordinates = (0..<100).map { Coordinate(latitude: Double($0), longitude: 0) }
        let snapshot = MirrorSnapshot(elapsed: 1_800, isPaused: false, distance: 5_000, heartRate: 150,
                                      zoneSeconds: [2: 300, 3: 1_200, 4: 300], coordinates: coordinates,
                                      goalName: workout.name,
                                      workoutProgress: MirrorWorkoutProgress(workout: workout, stepIndex: 5, remaining: .distance(250)))
        #expect(try JSONEncoder().encode(snapshot).count < 12_000)
    }
}
