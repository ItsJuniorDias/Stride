import SwiftUI
import StrideUI

/// End on the left in danger, Pause/Resume on the right in track, per the design system.
struct WatchControlsView: View {
    @Environment(WorkoutManager.self) private var workout

    var body: some View {
        HStack(spacing: Space.x3) {
            control("End", accessibilityLabel: "End run", systemImage: "xmark", tint: .danger, onTint: .onDanger) {
                workout.end()
            }
            if workout.phase == .paused {
                control("Resume", systemImage: "play.fill", tint: .track, onTint: .onTrack) { workout.resume() }
            } else {
                control("Pause", systemImage: "pause.fill", tint: .track, onTint: .onTrack) { workout.pause() }
            }
        }
        .scenePadding()
        .disabled(workout.isEnding)
        .opacity(workout.isEnding ? 0.3 : 1)
        .overlay {
            if workout.isEnding {
                ProgressView("Saving…")
            }
        }
    }

    private func control(_ title: String, accessibilityLabel: String? = nil, systemImage: String,
                         tint: Color, onTint: Color, action: @escaping () -> Void) -> some View {
        VStack(spacing: Space.x1) {
            Button(action: action) {
                // The glyph color goes on the label so the prominent style can't override it.
                Image(systemName: systemImage)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(onTint)
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent)
            .tint(tint)
            .accessibilityLabel(accessibilityLabel ?? title)
            Text(title)
                .font(.caption)
                .foregroundStyle(.inkMuted)
                .accessibilityHidden(true)
        }
    }
}
