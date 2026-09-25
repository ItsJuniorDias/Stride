import HealthKit
import SwiftUI
import WatchKit

@main
struct StrideWatchApp: App {
    @WKApplicationDelegateAdaptor private var appDelegate: WatchAppDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var workout = WorkoutManager.shared

    init() {
        WatchConnector.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environment(workout)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            WatchConnector.shared.retryPending()
            workout.updateLocationAccess()
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    /// iPhone asked to start a workout ("Start on Apple Watch").
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { await WorkoutManager.shared.startFromCompanion() }
    }

    /// watchOS relaunched the app during a workout after it crashed or was terminated.
    func handleActiveWorkoutRecovery() {
        Task { await WorkoutManager.shared.recoverActiveWorkout() }
    }

    /// Woken in the background: data from iPhone (the week for the complications) is handled; any
    /// other task is simply completed.
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let task = task as? WKWatchConnectivityRefreshBackgroundTask {
                WatchConnector.shared.handle(task)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
