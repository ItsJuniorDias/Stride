import SwiftUI

/// A round danger control that only fires after being held, so a stray tap can't end a run.
/// A ring fills around the button while it's held; releasing early resets it.
public struct HoldToConfirmButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let holdDuration: Double
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var confirmations = 0

    public init(
        systemImage: String = "stop.fill",
        accessibilityLabel: String = "Hold to finish",
        holdDuration: Double = 1.2,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.holdDuration = holdDuration
        self.action = action
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.line, lineWidth: 4)
                .padding(-7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.danger, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(-7)
            Circle().fill(Color.danger)
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(Color.onDanger)
        }
        .frame(width: Dimension.runControl, height: Dimension.runControl)
        .contentShape(Circle())
        .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 40) {
            confirmations += 1
            action()
        } onPressingChanged: { pressing in
            withAnimation(pressing ? .linear(duration: holdDuration) : .easeOut(duration: 0.2)) {
                progress = pressing ? 1 : 0
            }
        }
        .sensoryFeedback(.success, trigger: confirmations)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { action() }
    }
}
