import SwiftUI

/// Round 96pt control for the live run screen: Start, Pause or Resume.
/// Finish is a separate hold-to-confirm control, see ``HoldToConfirmButton``.
/// Start and Resume sit on a soft glow of the brand color; Pause is the ink circle.
public struct RunControlButton: View {
    public enum Kind: Sendable {
        case start, pause, resume

        var accessibilityLabel: String {
            switch self {
            case .start: "Start"
            case .pause: "Pause"
            case .resume: "Resume"
            }
        }
    }

    let kind: Kind
    let action: () -> Void
    @State private var taps = 0

    public init(_ kind: Kind, action: @escaping () -> Void) {
        self.kind = kind
        self.action = action
    }

    public var body: some View {
        Button {
            taps += 1
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(kind == .pause ? Color.ink : Color.track)
                    .shadow(color: glow, radius: 14, y: 10)
                label.foregroundStyle(kind == .pause ? Color.surface : Color.onTrack)
            }
            .frame(width: Dimension.runControl, height: Dimension.runControl)
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(kind.accessibilityLabel)
        .sensoryFeedback(.impact(weight: .medium), trigger: taps)
    }

    /// The brand glow under Start and Resume.
    private var glow: Color {
        switch kind {
        case .start: Color.track.opacity(0.35)
        case .resume: Color.track.opacity(0.3)
        case .pause: .clear
        }
    }

    @ViewBuilder private var label: some View {
        switch kind {
        case .start:
            Text("START")
                .font(.system(size: 17, weight: .heavy).width(.expanded))
                .tracking(0.7)
        case .pause:
            Image(systemName: "pause.fill").font(.system(size: 32, weight: .bold))
        case .resume:
            Image(systemName: "play.fill").font(.system(size: 32, weight: .bold))
        }
    }
}

struct PressScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
