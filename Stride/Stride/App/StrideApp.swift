import SwiftUI
import SwiftData
import StrideKit

@main
struct StrideApp: App {
    @State private var tracker = RunTracker()
    private let container: ModelContainer

    init() {
        do {
            container = try ModelContainer(for: Run.self, Shoe.self)
        } catch {
            fatalError("Could not open the Stride database: \(error)")
        }
        WatchSync.shared.activate(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(tracker)
        }
        .modelContainer(container)
    }
}
