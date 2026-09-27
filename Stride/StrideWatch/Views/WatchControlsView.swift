import SwiftUI
import WatchKit
import StrideKit
import StrideUI

/// The run's clock and status on top, then four round controls: Water Lock and New above, End
/// (danger) and Pause/Resume (track) below, where the thumb lands. Ending dims them behind
/// "Saving your run".
struct WatchControlsView: View {
    @Environment(WorkoutManager.self) private var workout
    /// End this run and go back to the start list for the next one.
    let onNew: () -> Void

    private let diameter: CGFloat = 58

    var body: some View {
        let isPaused = workout.phase == .paused
        VStack(alignment: .leading, spacing: Space.x3) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                header(elapsed: workout.elapsedTime(at: context.date), isPaused: isPaused)
            }

            Grid(horizontalSpacing: Space.x2, verticalSpacing: 10) {
                GridRow {
                    RoundIconButton("drop.fill", accessibilityLabel: "Water lock", diameter: diameter, title: "Lock") {
                        // Allowed while a workout is in the foreground; turning the crown unlocks.
                        WKInterfaceDevice.current().enableWaterLock()
                    }
                    RoundIconButton("plus", accessibilityLabel: "End and start a new run", diameter: diameter,
                                    title: "New", action: onNew)
                }
                GridRow {
                    RoundIconButton("xmark", accessibilityLabel: "End run", style: .tinted(.danger),
                                    diameter: diameter, title: "End") {
                        workout.end()
                    }
                    if isPaused {
                        RoundIconButton("play.fill", accessibilityLabel: "Resume", style: .filled(.track),
                                        diameter: diameter, title: "Resume") {
                            workout.resume()
                        }
                    } else {
                        RoundIconButton("pause.fill", accessibilityLabel: "Pause", style: .filled(.track),
                                        diameter: diameter, title: "Pause") {
                            workout.pause()
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .disabled(workout.isEnding)
            .opacity(workout.isEnding ? 0.15 : 1)
            .accessibilityHidden(workout.isEnding)
        }
        .padding(.horizontal, Space.x4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if workout.isEnding {
                VStack(spacing: 10) {
                    ProgressView()
                        .tint(.ink)
                    Text("Saving your run")
                        .watchFont(15, .semibold)
                        .foregroundStyle(.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    /// 24:18 in track (muted while paused), then what the run is for, or "Paused".
    private func header(elapsed: TimeInterval, isPaused: Bool) -> some View {
        HStack(spacing: 6) {
            Text(RunFormat.duration(elapsed))
                .font(.watchMetric(15, weight: .heavy))
                .foregroundStyle(isPaused ? Color.inkMuted : Color.track)
                .lineLimit(1)
                .fixedSize()
            WatchRunStatus(title: workout.goal.title, isPaused: isPaused, showsIcon: false)
        }
        .frame(minHeight: 22)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Time \(WatchSpeech.duration(elapsed)), \(isPaused ? "paused" : workout.goal.title)")
    }
}
