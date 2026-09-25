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
    /// watchOS relaunched the app during a workout after it crashed or was terminated.
    func handleActiveWorkoutRecovery() {
        Task { await WorkoutManager.shared.recoverActiveWorkout() }
    }
}
