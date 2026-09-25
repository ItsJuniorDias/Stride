import SwiftUI
import StrideUI

struct WatchCountdownView: View {
    @Environment(WorkoutManager.self) private var workout
    let number: Int

    var body: some View {
        VStack(spacing: Space.x2) {
            Text("\(number)")
                .font(.system(size: 96, weight: .heavy).width(.expanded))
                .monospacedDigit()
                .foregroundStyle(.track)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: number)
            // Once the activity has started, the run can only be ended from the workout pages.
            if workout.startDate == nil {
                Button("Cancel", role: .cancel) { workout.cancelCountdown() }
                    .buttonStyle(.plain)
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
            }
        }
    }
}
