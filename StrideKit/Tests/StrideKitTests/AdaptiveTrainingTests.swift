import Foundation
import Testing
import SwiftData
@testable import StrideKit

/// A fixed Gregorian calendar in UTC, so the tests don't depend on the machine.
private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 24, hour: 12))!

private func daysAgo(_ days: Int) -> Date {
    calendar.date(byAdding: .day, value: -days, to: now)!
}

/// 25:00 for 5K: 5'00" per km, easy 6'15"–6'45", tempo 5'24".
private let paces = TrainingPaces(fiveKTime: 1_500)!

/// Numbers with decimals as the device formats them (the simulator runs in pt_BR).
private func decimal(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0...2)))
}

@Suite struct AdaptivePlanTests {
    private let tenK = TrainingPlan.tenK
    private let half = TrainingPlan.halfMarathon

    @Test func sessionsKnowTheirIntensity() {
        let firstWeek = tenK.weeks[0]
        #expect(tenK.intensity(of: firstWeek[0]) == .easy)
        #expect(tenK.intensity(of: firstWeek[1]) == .interval)
        #expect(tenK.intensity(of: firstWeek[2]) == .easy)
        #expect(half.intensity(of: half.weeks[3][1]) == .threshold)
        // Race days and First 5K's run/walk are run by feel.
        #expect(tenK.intensity(of: tenK.weeks[7][2]) == nil)
        #expect(half.intensity(of: half.weeks[9][2]) == nil)
        #expect(TrainingPlan.firstFiveK.sessions.allSatisfy { TrainingPlan.firstFiveK.intensity(of: $0) == nil })
        #expect(tenK.usesPersonalPaces)
        #expect(!TrainingPlan.firstFiveK.usesPersonalPaces)
    }

    @Test func intervalSessionsGetTheIntervalPaceOnRunStepsOnly() {
        let session = tenK.weeks[2][1]
        let personal = tenK.personalized(session, paces: paces)
        #expect(personal.id == session.id)
        #expect(personal.steps.count == session.steps.count)
        #expect(personal.steps.map(\.id) == session.steps.map(\.id))
        for step in personal.steps {
            #expect(step.targetPace == (step.kind == .run ? 300 : nil))
        }
    }

    @Test func tempoGetsThresholdAndEasyRunsStayByFeel() {
        let tempo = half.personalized(half.weeks[0][1], paces: paces)
        #expect(tempo.steps.first { $0.kind == .run }?.targetPace == 1_500 / 5 * 1.08)
        let easy = half.weeks[0][0]
        #expect(half.personalized(easy, paces: paces) == easy)
        let race = tenK.weeks[7][2]
        #expect(tenK.personalized(race, paces: paces) == race)
    }

    @Test func aStepWithItsOwnTargetKeepsIt() {
        let session = Workout(id: tenK.weeks[0][1].id, name: "Intervals", detail: "",
                              steps: [WorkoutStep(.run, .distance(800), targetPace: 280)])
        #expect(tenK.personalized(session, paces: paces).steps[0].targetPace == 280)
    }

    @Test func suggestsRepeatingTheLastFullWeekAfterABreak() {
        let firstWeek = Set(tenK.weeks[0].map(\.id))
        #expect(tenK.suggestedRepeatWeek(completed: firstWeek, lastRunDate: daysAgo(15), now: now, calendar: calendar) == 0)
        #expect(tenK.suggestedRepeatWeek(completed: firstWeek, lastRunDate: daysAgo(10), now: now, calendar: calendar) == nil)
        #expect(tenK.suggestedRepeatWeek(completed: firstWeek, lastRunDate: nil, now: now, calendar: calendar) == nil)
        // Halfway through week 3: week 2 is the last one fully done.
        let partway = firstWeek.union(tenK.weeks[1].map(\.id)).union([tenK.weeks[2][0].id])
        #expect(tenK.suggestedRepeatWeek(completed: partway, lastRunDate: daysAgo(30), now: now, calendar: calendar) == 1)
        // Still in week 1, or done: nothing to repeat.
        #expect(tenK.suggestedRepeatWeek(completed: [], lastRunDate: daysAgo(30), now: now, calendar: calendar) == nil)
        let all = Set(tenK.sessions.map(\.id))
        #expect(tenK.suggestedRepeatWeek(completed: all, lastRunDate: daysAgo(30), now: now, calendar: calendar) == nil)
    }

    @Test func aRepeatRunsTheRepeatedWeeksThenCarriesOn() {
        let completed = Set(tenK.weeks[0...2].flatMap { $0 }.map(\.id))
        let repeating = PlanRepeat(planID: tenK.id, week: 1, since: daysAgo(1))
        let weekTwo = tenK.weeks[1].map(\.id)
        let weekThree = tenK.weeks[2].map(\.id)

        #expect(tenK.nextSession(completed: completed, repeating: repeating, runSince: [])?.id == weekTwo[0])
        #expect(tenK.nextSession(completed: completed, repeating: repeating, runSince: [weekTwo[0]])?.id == weekTwo[1])
        #expect(tenK.nextSession(completed: completed, repeating: repeating, runSince: Set(weekTwo))?.id == weekThree[0])
        // Every repeated session run: back to where the plan was.
        let done = Set(weekTwo + weekThree)
        #expect(tenK.repeatedSession(completed: completed, repeating: repeating, runSince: done) == nil)
        #expect(tenK.nextSession(completed: completed, repeating: repeating, runSince: done)?.id == tenK.weeks[3][0].id)
        // Nothing is marked done or undone along the way.
        #expect(tenK.progress(completed: completed) == 9.0 / 24.0)
    }

    @Test func aRepeatOnlyAppliesToItsPlanAndToWeeksBehindTheRunner() {
        let completed = Set(tenK.weeks[0].map(\.id))
        let other = PlanRepeat(planID: "half", week: 0, since: now)
        #expect(tenK.repeatedSession(completed: completed, repeating: other, runSince: []) == nil)
        // A repeat from week 3 when the runner is in week 2 (a session was marked not done since).
        let ahead = PlanRepeat(planID: tenK.id, week: 2, since: now)
        #expect(tenK.repeatedSession(completed: completed, repeating: ahead, runSince: []) == nil)
        let outside = PlanRepeat(planID: tenK.id, week: 40, since: now)
        #expect(tenK.repeatedSession(completed: completed, repeating: outside, runSince: []) == nil)
    }

    @Test func repeatSurvivesItsStringSetting() throws {
        let repeating = PlanRepeat(planID: "10k", week: 2, since: Date(timeIntervalSince1970: 1_758_800_000.7))
        let restored = try #require(PlanRepeat(rawValue: repeating.rawValue))
        #expect(restored.planID == "10k")
        #expect(restored.week == 2)
        #expect(restored.since == Date(timeIntervalSince1970: 1_758_800_000))
        #expect(PlanRepeat(rawValue: "") == nil)
        #expect(PlanRepeat(rawValue: "10k|x|1") == nil)
        #expect(PlanRepeat(rawValue: "|1|1") == nil)
        #expect(PlanRepeat(rawValue: "10k|-1|1") == nil)
    }

    @Test func pacesReadInTheRunnersUnit() {
        #expect(paces.formatted(.easy, unit: .metric) == "6'15\"–6'45\" /km")
        #expect(paces.formatted(.threshold, unit: .metric) == "5'24\" /km")
        #expect(paces.formatted(.interval, unit: .imperial) == "8'03\" /mi")
        #expect(paces.coachedPace(.easy) == nil)
        #expect(paces.coachedPace(.interval) == 300)
    }

    @Test func repeatLengthSuggestsAPace() {
        #expect(TrainingPaces.Intensity.suited(to: .distance(400)) == .repetition)
        #expect(TrainingPaces.Intensity.suited(to: .distance(800)) == .interval)
        #expect(TrainingPaces.Intensity.suited(to: .distance(1_609.344)) == .interval)
        #expect(TrainingPaces.Intensity.suited(to: .distance(3_000)) == .threshold)
        #expect(TrainingPaces.Intensity.suited(to: .time(60)) == .repetition)
        #expect(TrainingPaces.Intensity.suited(to: .time(240)) == .interval)
        #expect(TrainingPaces.Intensity.suited(to: .time(600)) == .threshold)
    }
}

@Suite struct WorkoutBlueprintTests {
    private let pacedStarter: WorkoutBlueprint = {
        var blueprint = WorkoutBlueprint.starter
        blueprint.workPace = 290
        return blueprint
    }()

    @Test func laysOutWarmUpRepeatsAndCoolDown() {
        let steps = WorkoutBlueprint.starter.steps
        // Warm-up, 6 runs with 5 recoveries between them, cool-down.
        #expect(steps.count == 13)
        #expect(steps.first?.kind == .warmup)
        #expect(steps.last?.kind == .cooldown)
        #expect(steps.filter { $0.kind == .run }.count == 6)
        #expect(steps.filter { $0.kind == .recover }.count == 5)
        #expect(steps.map(\.id) == Array(0..<13))
    }

    @Test func readsItsOwnStepsBack() {
        #expect(WorkoutBlueprint(steps: pacedStarter.steps) == pacedStarter)
        let bare = WorkoutBlueprint(warmup: nil, repeats: 10, work: .time(30), recovery: .time(30), cooldown: nil)
        #expect(WorkoutBlueprint(steps: bare.steps) == bare)
        // A single repeat has no recovery to keep.
        let single = WorkoutBlueprint(warmup: .time(600), repeats: 1, work: .time(1_200), workPace: 320,
                                      recovery: .time(120), cooldown: .time(600))
        var expected = single
        expected.recovery = nil
        #expect(WorkoutBlueprint(steps: single.steps) == expected)
        #expect(IntervalPresets.all[0].steps.count == 17)
        #expect(WorkoutBlueprint(steps: IntervalPresets.all[0].steps)?.repeats == 8)
    }

    @Test func refusesStepsItCantMake() {
        let pyramid = IntervalPresets.all.first { $0.id == "preset-pyramid" }!
        #expect(WorkoutBlueprint(steps: pyramid.steps) == nil)
        #expect(WorkoutBlueprint(steps: []) == nil)
        #expect(WorkoutBlueprint(steps: [.time(.warmup, minutes: 10)]) == nil)
        #expect(WorkoutBlueprint(steps: [.time(.run, minutes: 2), .time(.recover, minutes: 1)]) == nil)
    }

    @Test func namesAndDescribesTheWorkout() {
        #expect(pacedStarter.defaultName(unit: .metric) == "6 × 800 m")
        #expect(pacedStarter.detail(unit: .metric) == "6 × 800 m at 4'50\" /km, 2 min recoveries · Warm-up 10 min, cool-down 5 min")
        let single = WorkoutBlueprint(warmup: nil, repeats: 1, work: .time(1_200), recovery: nil, cooldown: .time(300))
        #expect(single.defaultName(unit: .metric) == "20 min run")
        #expect(single.detail(unit: .metric) == "20 min run · Cool-down 5 min")
    }

    @Test func stepLengthsReadShort() {
        #expect(WorkoutBlueprint.text(for: .time(30), unit: .metric) == "30 s")
        #expect(WorkoutBlueprint.text(for: .time(90), unit: .metric) == "90 s")
        #expect(WorkoutBlueprint.text(for: .time(120), unit: .metric) == "2 min")
        #expect(WorkoutBlueprint.text(for: .time(150), unit: .metric) == "2:30 min")
        #expect(WorkoutBlueprint.text(for: .distance(400), unit: .metric) == "400 m")
        #expect(WorkoutBlueprint.text(for: .distance(1_500), unit: .metric) == "\(decimal(1.5)) km")
        #expect(WorkoutBlueprint.text(for: .distance(1_609.344), unit: .imperial) == "1 mi")
        #expect(WorkoutBlueprint.text(for: .distance(402.336), unit: .imperial) == "\(decimal(0.25)) mi")
        #expect(WorkoutBlueprint.text(for: .distance(1_200), unit: .imperial) == "1200 m")
        #expect(WorkoutBlueprint.text(for: .time(.infinity), unit: .metric) == "0 s")
    }

    @Test func estimatesTimeAndDistance() {
        let steps = [WorkoutStep(.warmup, .time(600)), WorkoutStep(.run, .distance(1_000), targetPace: 300),
                     WorkoutStep(.recover, .time(120)), WorkoutStep(.run, .distance(1_000)), WorkoutStep(.cooldown, .time(300))]
        let estimate = WorkoutEstimate(steps: steps, easyPace: 400, runPace: 330)
        #expect(estimate.stepDurations == [600, 300, 120, 330, 300])
        #expect(estimate.duration == 1_650)
        #expect(abs(estimate.distance - 4_550) < 1e-9)
        #expect(!estimate.isDurationExact)
        #expect(!estimate.isDistanceExact)

        let timed = WorkoutEstimate(steps: [WorkoutStep(.run, .time(600)), WorkoutStep(.recover, .time(60))])
        #expect(timed.isDurationExact)
        #expect(timed.duration == 660)
    }
}

@Suite struct CustomWorkoutTests {
    @MainActor
    @Test func runsAsAWorkoutTheCursorFollows() throws {
        let container = try ModelContainer(for: CustomWorkout.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let blueprint = WorkoutBlueprint(warmup: .time(60), repeats: 2, work: .distance(400), workPace: 240,
                                         recovery: .time(30), cooldown: nil)
        let custom = CustomWorkout(name: "  Track 400s ", steps: blueprint.steps)
        container.mainContext.insert(custom)

        let workout = custom.workout(unit: .metric)
        #expect(workout.id == "custom-\(custom.id.uuidString)")
        #expect(workout.name == "Track 400s")
        #expect(workout.detail == "2 × 400 m at 4'00\" /km, 30 s recoveries · Warm-up 1 min")
        #expect(workout.runStepCount == 2)
        #expect(custom.blueprint == blueprint)
        #expect(custom.isRunnable)

        var cursor = WorkoutCursor(workout: workout)
        #expect(cursor.advance(elapsed: 60, distance: 150) == [.stepStarted(workout.steps[1])])
        #expect(cursor.advance(elapsed: 150, distance: 550) == [.stepStarted(workout.steps[2])])
        #expect(cursor.advance(elapsed: 180, distance: 600) == [.stepStarted(workout.steps[3])])
        #expect(cursor.advance(elapsed: 280, distance: 1_000) == [.workoutCompleted])
        #expect(workout.steps[1].targetPace == 240)
    }

    @MainActor
    @Test func unreadableStepsDontRun() {
        let custom = CustomWorkout(name: "", steps: [])
        custom.stepsData = Data("not json".utf8)
        #expect(custom.steps.isEmpty)
        #expect(!custom.isRunnable)
        #expect(custom.displayName == "Workout")
    }
}
