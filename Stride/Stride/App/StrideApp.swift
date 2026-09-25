import SwiftUI
import SwiftData
import StrideKit

@main
struct StrideApp: App {
    @State private var tracker: RunTracker
    @State private var mirrored = MirroredWorkout.shared
    private let container: ModelContainer

    /// One database for the app and the intents Siri runs without opening it.
    static let sharedContainer: ModelContainer = {
        do {
            // Kept in the app's own container, where it has always been. With the App Group the
            // default configuration would put it in the shared container instead; widgets don't
            // need it (they read a small snapshot), and moving it risks leaving the runs behind.
            let schema = Schema([Run.self, Shoe.self, Challenge.self])
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, groupContainer: .none))
        } catch {
            fatalError("Could not open the Stride database: \(error)")
        }
    }()

    init() {
        container = Self.sharedContainer
        let tracker = RunTracker()
        _tracker = State(initialValue: tracker)
        // Siri, the Live Activity's buttons and the Control Center control act on this run.
        RunIntentBridge.handler = tracker
        WatchSync.shared.activate(container: container)
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
