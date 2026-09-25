import SwiftUI
import SwiftData
import HealthKit
import UIKit
import StrideKit

@main
struct StrideApp: App {
    @UIApplicationDelegateAdaptor private var appDelegate: StrideAppDelegate
    @State private var tracker: RunTracker
    @State private var mirrored = MirroredWorkout.shared
    private let container: ModelContainer

    /// One database for the app and the intents Siri runs without opening it.
    static let sharedContainer: ModelContainer = CloudStore.makeContainer()

    init() {
        container = Self.sharedContainer
        let tracker = RunTracker()
        _tracker = State(initialValue: tracker)
        // Siri, the Live Activity's buttons and the Control Center control act on this run.
        RunIntentBridge.handler = tracker
        WatchSync.shared.activate(container: container)
        SettingsSync.shared.start()
        // Must be installed at launch: HealthKit may start the app just to hand over a Watch workout.
        MirroredWorkout.shared.activate()
        // Also at launch, so no renewal, refund or Family Sharing change is missed.
        ProStore.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(tracker)
                .environment(mirrored)
        }
        .modelContainer(container)
    }
}

/// Stride on Apple Watch can hand Health's permission request to iPhone. Health then opens this app
/// and calls this method; the sheet shown here answers for the Watch.
final class StrideAppDelegate: NSObject, UIApplicationDelegate {
    func applicationShouldRequestHealthAuthorization(_ application: UIApplication) {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let store = MirroredWorkout.shared.healthStore
        Task {
            // Shows the types the Watch asked for; throws only if the request itself failed.
            try? await store.handleAuthorizationForExtension()
        }
    }
}
