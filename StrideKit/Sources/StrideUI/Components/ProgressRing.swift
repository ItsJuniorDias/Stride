import SwiftUI

/// Circular goal progress. Turns `success` once the goal is reached.
public struct ProgressRing<Center: View>: View {
    let progress: Double
    let lineWidth: CGFloat
    let center: Center

    public init(progress: Double, lineWidth: CGFloat = 12, @ViewBuilder center: () -> Center) {
        self.progress = progress
        self.lineWidth = lineWidth
        self.center = center()
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Color.surfaceSunken, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(progress >= 1 ? Color.success : Color.track,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .padding(lineWidth / 2)
        .animation(.snappy, value: progress)
    }
}

public extension ProgressRing where Center == EmptyView {
    init(progress: Double, lineWidth: CGFloat = 12) {
        self.init(progress: progress, lineWidth: lineWidth) { EmptyView() }
    }
}
