import Foundation
import Observation
import StrideKit

/// The coach during an iPhone run: follows the workout's steps, watches the target pace, announces
/// splits, goal progress and pauses. Fed by ``RunTracker``; the live screen reads its state.
///
/// Workout steps run on a step clock that keeps going through auto-pause (a recovery taken standing
/// still still ends) but stops for a manual pause. Goals, splits and pace use moving time.
@Observable
final class RunCoach {
    /// The workout being followed, if the run has one.
    private(set) var cursor: WorkoutCursor?
    private(set) var stepRemaining: WorkoutStep.Goal?
    private(set) var stepProgress: Double = 0
    /// Where the runner is against the target pace; nil when there's no target right now.
    private(set) var paceStatus: PaceGuard.Status?
    /// Incremented on step changes, for haptics.
    private(set) var stepEvents = 0

    var workoutComplete: Bool { cursor?.isFinished ?? false }

    let voice = VoiceCoach()

    @ObservationIgnored private var unit: UnitSystem = .metric
    @ObservationIgnored private var runTargetPace: Double?
    @ObservationIgnored private var paceGuard: PaceGuard?
    @ObservationIgnored private var paceGuardStepID: Int?
    @ObservationIgnored private var goalDistance: Double?
    @ObservationIgnored private var goalDuration: TimeInterval?
    @ObservationIgnored private var halfwayAnnounced = false
    @ObservationIgnored private var goalAnnounced = false
    @ObservationIgnored private var announceEvery: Double = 1_000
    @ObservationIgnored private var nextAnnouncement: Double = 1_000
    @ObservationIgnored private var lastAnnouncement: (distance: Double, elapsed: TimeInterval) = (0, 0)

    /// What the coach needs to pick up a restored run where it left off.
    struct Snapshot: Codable {
        var cursor: WorkoutCursor?
        var nextAnnouncement: Double
        var lastAnnouncementDistance: Double
        var lastAnnouncementElapsed: TimeInterval
        var halfwayAnnounced: Bool
        var goalAnnounced: Bool
    }

    var snapshot: Snapshot {
        Snapshot(cursor: cursor, nextAnnouncement: nextAnnouncement,
                 lastAnnouncementDistance: lastAnnouncement.distance, lastAnnouncementElapsed: lastAnnouncement.elapsed,
                 halfwayAnnounced: halfwayAnnounced, goalAnnounced: goalAnnounced)
    }

    /// Starts coaching a run.
    func begin(_ configuration: RunTracker.Configuration, unit: UnitSystem) {
        configure(configuration, unit: unit)
        voice.speak(CoachScript.start(workout: configuration.workout))
        if let step = cursor?.currentStep, let workout = configuration.workout {
            voice.speak(CoachScript.stepStarted(step, in: workout, unit: unit))
        }
        updateStepState(stepClock: 0, distance: 0)
    }

    /// Silently picks up a run restored after the app was terminated.
    func restore(_ configuration: RunTracker.Configuration, unit: UnitSystem, snapshot: Snapshot?,
                 elapsed: TimeInterval, stepClock: TimeInterval, distance: Double) {
        configure(configuration, unit: unit)
        if let snapshot {
            cursor = snapshot.cursor
            nextAnnouncement = snapshot.nextAnnouncement
            lastAnnouncement = (snapshot.lastAnnouncementDistance, snapshot.lastAnnouncementElapsed)
            halfwayAnnounced = snapshot.halfwayAnnounced
            goalAnnounced = snapshot.goalAnnounced
        } else {
            // A checkpoint from before the snapshot existed: approximate from the totals.
            while nextAnnouncement <= distance { nextAnnouncement += announceEvery }
            lastAnnouncement = (distance, elapsed)
            let progress = progress(elapsed: elapsed, distance: distance) ?? 0
            halfwayAnnounced = progress >= 0.5
            goalAnnounced = progress >= 1
        }
        _ = cursor?.advance(elapsed: stepClock, distance: distance)
        updateStepState(stepClock: stepClock, distance: distance)
    }

    private func configure(_ configuration: RunTracker.Configuration, unit: UnitSystem) {
        reset()
        self.unit = unit
        goalDistance = configuration.targetDistance
        goalDuration = configuration.targetDuration
        runTargetPace = configuration.targetPace.map { $0 * unit.metersPerUnit / 1_000 }
        let interval = UserDefaults.standard.double(forKey: StrideSettings.voiceInterval)
        announceEvery = (interval > 0 ? interval : 1) * unit.metersPerUnit
        nextAnnouncement = announceEvery
        cursor = configuration.workout.map { WorkoutCursor(workout: $0) }
    }

    /// Called every clock tick while running and not auto-paused.
    func tick(elapsed: TimeInterval, stepClock: TimeInterval, distance: Double,
              currentPace: Double?, averagePace: Double?, now: Date = .now) {
        advanceSteps(stepClock: stepClock, distance: distance, announce: true)

        // Distance or time goal.
        if let progress = progress(elapsed: elapsed, distance: distance) {
            if progress >= 1, !goalAnnounced {
                goalAnnounced = true
                halfwayAnnounced = true
                voice.speak(CoachScript.goalReached)
            } else if progress >= 0.5, !halfwayAnnounced {
                halfwayAnnounced = true
                voice.speak(CoachScript.goalHalfway(remaining: remainingGoalText(elapsed: elapsed, distance: distance)))
            }
        }

        // Splits.
        if distance >= nextAnnouncement {
            let splitPace = RunFormat.paceSeconds(distance: distance - lastAnnouncement.distance,
                                                  duration: elapsed - lastAnnouncement.elapsed, unit: unit)
            voice.speak(CoachScript.split(
                distance: nextAnnouncement, elapsed: elapsed, averagePace: averagePace, lastSplitPace: splitPace, unit: unit,
                splitLength: announceEvery / unit.metersPerUnit,
                includeTime: StrideSettings.bool(StrideSettings.voiceIncludeTime),
                includePace: StrideSettings.bool(StrideSettings.voiceIncludePace)
            ))
            lastAnnouncement = (distance, elapsed)
            while nextAnnouncement <= distance { nextAnnouncement += announceEvery }
        }

        // Target pace, only while running (never during warm-up, recoveries or cool-down).
        guard let target = activeTargetPace else {
            clearPace()
            return
        }
        let stepID = cursor?.currentStep?.id
        if paceGuard?.target != target || paceGuardStepID != stepID {
            paceGuard = PaceGuard(target: target)
            paceGuardStepID = stepID
        }
        if let alert = paceGuard?.evaluate(currentPace: currentPace, at: now) {
            voice.speak(CoachScript.pace(alert, unit: unit))
        }
        paceStatus = paceGuard?.status
    }

    /// Called every tick while auto-paused: only the workout steps move (on the step clock).
    func tickSteps(stepClock: TimeInterval, distance: Double) {
        advanceSteps(stepClock: stepClock, distance: distance, announce: true)
    }

    /// Catches the steps up without speaking, e.g. right before a pause or finish.
    func sync(stepClock: TimeInterval, distance: Double) {
        advanceSteps(stepClock: stepClock, distance: distance, announce: false)
    }

    func paused() {
        clearPace()
        voice.speak(CoachScript.paused)
    }

    func resumed() {
        clearPace()
        voice.speak(CoachScript.resumed)
    }

    func autoPaused() {
        clearPace()
        voice.speak(CoachScript.autoPaused)
    }

    func autoResumed() {
        clearPace()
        voice.speak(CoachScript.autoResumed)
    }

    func finished(distance: Double, elapsed: TimeInterval) {
        voice.speak(CoachScript.finished(distance: distance, elapsed: elapsed, unit: unit))
    }

    /// Stops speaking but keeps the state, so the live screen doesn't change while it closes.
    func silence() {
        voice.stop()
    }

    /// Clears the run. `stopVoice: false` lets a last line (e.g. "Run finished") play out.
    func reset(stopVoice: Bool = true) {
        if stopVoice { voice.stop() }
        cursor = nil
        stepRemaining = nil
        stepProgress = 0
        clearPace()
        goalDistance = nil
        goalDuration = nil
        runTargetPace = nil
        halfwayAnnounced = false
        goalAnnounced = false
        nextAnnouncement = announceEvery
        lastAnnouncement = (0, 0)
    }

    // MARK: Helpers

    private func advanceSteps(stepClock: TimeInterval, distance: Double, announce: Bool) {
        guard var cursor else { return }
        let workout = cursor.workout
        for event in cursor.advance(elapsed: stepClock, distance: distance) {
            stepEvents += 1
            guard announce else { continue }
            switch event {
            case .stepStarted(let step): voice.speak(CoachScript.stepStarted(step, in: workout, unit: unit))
            case .workoutCompleted: voice.speak(CoachScript.workoutCompleted)
            }
        }
        self.cursor = cursor
        updateStepState(stepClock: stepClock, distance: distance)
    }

    /// A fresh guard after every pause, so a stale off-pace window can't fire right after resuming.
    private func clearPace() {
        paceGuard = nil
        paceGuardStepID = nil
        paceStatus = nil
    }

    /// Seconds per unit to hold right now: the step's own target, else the run's target during run steps.
    private var activeTargetPace: Double? {
        if let cursor {
            guard let step = cursor.currentStep, step.kind == .run else { return nil }
            return step.targetPace.map { $0 * unit.metersPerUnit / 1_000 } ?? runTargetPace
        }
        return runTargetPace
    }

    private func updateStepState(stepClock: TimeInterval, distance: Double) {
        stepRemaining = cursor?.remaining(elapsed: stepClock, distance: distance)
        stepProgress = cursor?.stepProgress(elapsed: stepClock, distance: distance) ?? 0
    }

    private func progress(elapsed: TimeInterval, distance: Double) -> Double? {
        if let goalDistance, goalDistance > 0 { return distance / goalDistance }
        if let goalDuration, goalDuration > 0 { return elapsed / goalDuration }
        return nil
    }

    private func remainingGoalText(elapsed: TimeInterval, distance: Double) -> String {
        if let goalDistance { return CoachScript.spokenDistance(max(goalDistance - distance, 0), unit: unit) }
        if let goalDuration { return CoachScript.spokenDuration(max(goalDuration - elapsed, 0)) }
        return ""
    }
}
