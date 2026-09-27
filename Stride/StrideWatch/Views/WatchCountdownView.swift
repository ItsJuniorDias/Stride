import SwiftUI
import StrideKit
import StrideUI

/// 3, 2, 1 in a ring of three arcs that go out one per second, with what the run is for underneath.
/// Cancel stays until the activity starts; after that the run can only be ended from its pages.
struct WatchCountdownView: View {
    @Environment(WorkoutManager.self) private var workout
    let number: Int

    var body: some View {
        VStack(spacing: Space.x2) {
            ZStack {
                CountdownRing(remaining: number)
                VStack(spacing: 2) {
                    Text("\(number)")
                        .font(.watchMetric(72, weight: .heavy))
                        .foregroundStyle(.track)
                        .contentTransition(.numericText(countsDown: true))
                    Text(workout.goal.title)
                        .watchFont(13, .medium)
                        .foregroundStyle(.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, Space.x5)
                }
            }
            // As large as drawn, smaller only where a small Watch needs the room for Cancel.
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 156, maxHeight: 156)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Starting in \(number)")
            .accessibilityValue(workout.goal.title)
            .layoutPriority(1)

            if workout.startDate == nil {
                Spacer(minLength: 0)
                Button("Cancel", role: .cancel) { workout.cancelCountdown() }
                    .buttonStyle(WatchCapsuleButtonStyle(fill: .surfaceRaised, foreground: .ink, fontSize: 15, fillsWidth: false))
            }
        }
        .animation(.snappy, value: number)
        .padding(.top, Space.x2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Three 106° arcs with 14° gaps at 12, 4 and 8 o'clock. They go out counterclockwise, one per
/// second: the left arc at 2, the bottom one at 1.
private struct CountdownRing: View {
    let remaining: Int

    /// Where each arc starts, clockwise from 3 o'clock.
    private static let starts: [Double] = [-83, 37, 157]
    private static let sweep = 106.0 / 360

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            // Drawn at 148 pt: radius 66, line 8.
            let inset = side * 8 / 148
            ZStack {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .trim(from: 0, to: Self.sweep)
                        .stroke(index < remaining ? Color.track : Color.surfaceRaised,
                                style: StrokeStyle(lineWidth: inset, lineCap: .round))
                        .rotationEffect(.degrees(Self.starts[index]))
                        .padding(inset)
                }
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .accessibilityHidden(true)
    }
}
