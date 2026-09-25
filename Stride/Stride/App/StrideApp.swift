import SwiftUI
import SwiftData
import StrideKit

@main
struct StrideApp: App {
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
