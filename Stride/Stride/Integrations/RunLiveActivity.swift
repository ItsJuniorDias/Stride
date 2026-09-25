import Foundation
import ActivityKit
import StrideKit

/// The run on the Lock Screen, in the Dynamic Island and in Apple Watch's Smart Stack. The clock
/// and step countdowns count on their own; an update is sent when something else visible changes
/// (status, step) and otherwise every 15 seconds for distance and pace.
@MainActor
final class RunLiveActivity {
    typealias State = RunActivityAttributes.ContentState

    private var activity: Activity<RunActivityAttributes>?
    private var lastSent: State?
    private var lastSentAt = Date.distantPast
    /// A request refused (the app was in the background) isn't retried on every tick.
    private var nextRequestAt = Date.distantPast
    /// Activities asked to end whose end hasn't landed yet: never picked up again.
    private var endingIDs: Set<String> = []

    /// Sends `state` if enough changed since the last update, starting the activity if there's none.
    func sync(_ state: State, title: String, unit: UnitSystem) {
        // Ended or dismissed from outside (e.g. swiped away): start over.
        if let current = activity, current.activityState == .ended || current.activityState == .dismissed {
            activity = nil
            lastSent = nil
        }
        if activity == nil {
            // After a relaunch the activity from before is still on the Lock Screen: carry on with it.
            activity = Activity<RunActivityAttributes>.activities.first {
                ($0.activityState == .active || $0.activityState == .stale) && $0.content.state.status != .finished
                    && !endingIDs.contains($0.id)
            }
        }
        guard let activity else {
            guard ActivityAuthorizationInfo().areActivitiesEnabled, Date.now >= nextRequestAt else { return }
            // A finished run's card from before gives way to the new run.
            for old in Activity<RunActivityAttributes>.activities {
                endingIDs.insert(old.id)
                nonisolated(unsafe) let target = old
                Task { await target.end(nil, dismissalPolicy: .immediate) }
            }
            do {
                self.activity = try Activity.request(attributes: RunActivityAttributes(title: title, unit: unit),
                                                     content: content(state))
                lastSent = state
                lastSentAt = .now
            } catch {
                // Only the foreground may start one; try again once the app is back.
                nextRequestAt = .now.addingTimeInterval(20)
            }
            return
        }
        let visibleChange = lastSent.map {
            $0.status != state.status || $0.step != state.step || $0.resumeInApp != state.resumeInApp
                || ($0.clockStart != nil) != (state.clockStart != nil)
                || moved($0.stepEnd, state.stepEnd)
        } ?? true
        // A clock start that drifted over a second means the time shown is off: resync it.
        let clockDrift = moved(lastSent?.clockStart, state.clockStart)
        guard visibleChange || clockDrift || Date.now.timeIntervalSince(lastSentAt) >= 15 else { return }
        lastSent = state
        lastSentAt = .now
        // Activity isn't Sendable, but ActivityKit expects updates from any task.
        nonisolated(unsafe) let target = activity
        let content = content(state)
        Task { await target.update(content) }
    }

    /// Ends every run activity: showing the final numbers for a while, or right away.
    func end(_ state: State?, immediately: Bool) {
        activity = nil
        lastSent = nil
        lastSentAt = .distantPast
        nextRequestAt = .distantPast
        let content = state.map { ActivityContent(state: $0, staleDate: nil) }
        let policy: ActivityUIDismissalPolicy = immediately ? .immediate : .after(.now.addingTimeInterval(15 * 60))
        for activity in Activity<RunActivityAttributes>.activities {
            endingIDs.insert(activity.id)
            nonisolated(unsafe) let target = activity
            Task { await target.end(content, dismissalPolicy: policy) }
        }
    }

    /// A counting clock goes stale a minute after the last update (updates come every 15 s), so if
    /// the app dies the Lock Screen stops counting. Paused numbers don't move and never go stale.
    private func content(_ state: State) -> ActivityContent<State> {
        ActivityContent(state: state, staleDate: state.status == .running ? .now.addingTimeInterval(60) : nil)
    }

    /// Two dates differ by more than a second, or one is missing.
    private func moved(_ a: Date?, _ b: Date?) -> Bool {
        switch (a, b) {
        case let (a?, b?): abs(a.timeIntervalSince(b)) > 1
        case (nil, nil): false
        default: true
        }
    }
}


extension RunLiveActivity {
    /// Ends activities for runs that are gone (the app was terminated and there's nothing to restore).
    /// A finished run's activity stays up with its final numbers.
    func endAbandoned() {
        for activity in Activity<RunActivityAttributes>.activities where activity.content.state.status != .finished {
            endingIDs.insert(activity.id)
            nonisolated(unsafe) let target = activity
            Task { await target.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
