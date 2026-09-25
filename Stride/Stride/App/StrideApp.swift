import SwiftUI
import SwiftData
import StrideKit

@main
struct StrideApp: App {
    @State private var tracker = RunTracker()
    @State private var mirrored = MirroredWorkout.shared
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Run.self, Shoe.self)
        } catch {
            fatalError("Could not open the Stride database: \(error)")
        }
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
