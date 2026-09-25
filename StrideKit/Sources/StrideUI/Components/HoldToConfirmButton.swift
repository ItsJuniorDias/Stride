import SwiftUI

/// A round control that only fires after being held, so a stray tap can't end a run.
/// A ring fills around the button while it's held; releasing early resets it.
/// Defaults to the `danger` fill used by Finish; the unlock control passes `ink`.
/// Pass `confirmationTitle` for destructive actions: VoiceOver and Switch Control users get a
/// confirmation dialog in place of the hold.
public struct HoldToConfirmButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let holdDuration: Double
    let fill: Color
    let foreground: Color
    let confirmationTitle: String?
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var confirmations = 0
    @State private var confirmingAccessibly = false

    public init(
        systemImage: String = "stop.fill",
        accessibilityLabel: String = "Hold to finish",
        holdDuration: Double = 1.2,
        fill: Color = .danger,
        foreground: Color = .onDanger,
        confirmationTitle: String? = nil,
        action: @escaping () -> Void
    ) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.holdDuration = holdDuration
        self.fill = fill
        self.foreground = foreground
        self.confirmationTitle = confirmationTitle
        self.action = action
    }

    public var body: some View {
        ZStack {
            Circle()
                .stroke(Color.line, lineWidth: 4)
                .padding(-7)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(fill, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(-7)
            Circle().fill(fill)
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(foreground)
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
        // Assistive technologies can't hold, so they get a confirmation step instead of skipping it.
        .accessibilityAction {
            if confirmationTitle != nil {
                confirmingAccessibly = true
            } else {
                confirmations += 1
                action()
            }
        }
        .confirmationDialog(confirmationTitle ?? "", isPresented: $confirmingAccessibly, titleVisibility: .visible) {
            Button("Confirm", role: .destructive) {
                confirmations += 1
                action()
            }
        }
    }
}
