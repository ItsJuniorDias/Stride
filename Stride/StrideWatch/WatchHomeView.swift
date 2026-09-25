import SwiftUI
import StrideUI

/// Placeholder start screen. The workout session arrives in phase 2.
struct WatchHomeView: View {
    var body: some View {
        NavigationStack {
            List {
                Button {
                } label: {
                    Label("Free run", systemImage: "figure.run")
                        .font(.headline)
                }
                .listItemTint(.track)

                Section("Workouts") {
                    Label("Distance", systemImage: "ruler")
                    Label("Time", systemImage: "stopwatch")
                    Label("Intervals", systemImage: "repeat")
                }
            }
            .navigationTitle("Stride")
        }
    }
}

#Preview {
    WatchHomeView()
}
