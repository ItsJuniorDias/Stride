import SwiftUI
import StrideUI

/// Switches between the start list, countdown, live workout pages and summary.
struct WatchRootView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        content
            .alert("Workout problem", isPresented: errorAlert) {
                Button("OK") {}
            } message: {
                Text(workout.workoutError ?? "")
            }
    }

    @ViewBuilder private var content: some View {
        switch workout.phase {
        case .idle:
            WatchHomeView()
        case .countdown(let number):
            WatchCountdownView(number: number)
        case .running, .paused:
            SessionPagingView()
        case .ended:
            WatchSummaryView()
        }
    }

    private var errorAlert: Binding<Bool> {
        Binding(get: { workout.workoutError != nil }, set: { if !$0 { workout.clearWorkoutError() } })
    }
}
