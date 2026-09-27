import SwiftUI
import StrideUI

/// Switches between the start list, countdown, live workout pages and summary.
struct WatchRootView: View {
    @Environment(WorkoutManager.self) private var workout
    /// New was tapped on the controls: once the run is saved, skip its summary and go back to the
    /// start list for the next run.
    @State private var startsNewRun = false

    var body: some View {
        content
            .alert(workout.workoutErrorTitle, isPresented: errorAlert) {
                Button("OK") {}
            } message: {
                Text(workout.workoutError ?? "")
            }
            .onChange(of: workout.phase) { _, phase in
                switch phase {
                case .ended where startsNewRun:
                    startsNewRun = false
                    workout.reset()
                case .idle:
                    startsNewRun = false
                default:
                    break
                }
            }
    }

    @ViewBuilder private var content: some View {
        switch workout.phase {
        case .idle:
            WatchHomeView()
        case .countdown(let number):
            WatchCountdownView(number: number)
        case .running, .paused:
            SessionPagingView(onNew: { endAndStartNew() })
        case .ended:
            if startsNewRun {
                ProgressView()
            } else {
                WatchSummaryView()
            }
        }
    }

    /// Ends and saves the run like End does; only a run that is actually ending skips its summary.
    private func endAndStartNew() {
        guard !workout.isEnding else { return }
        workout.end()
        startsNewRun = workout.isEnding
    }

    private var errorAlert: Binding<Bool> {
        Binding(get: { workout.workoutError != nil }, set: { if !$0 { workout.clearWorkoutError() } })
    }
}
