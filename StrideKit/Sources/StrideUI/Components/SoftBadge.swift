import SwiftUI

/// A small filled capsule beside a title, for a state rather than an action: "Default" on a shoe
/// (`.lane`), "Next" on a plan session (`.brand`, uppercase), "Active" on Stride Pro (`.neutral`
/// with a `success` dot), "Plan" on a Watch workout, "Manual" on a typed-in run (`.muted`). For the
/// outlined PRO tag use ``TagBadge``; for a status with more words use ``StatusChip``.
public struct SoftBadge: View {
    public enum Tone: Sendable {
        /// `trackSoft` with `track` text.
        case brand
        /// `laneSoft` with `lane` text.
        case lane
        /// `surfaceSunken` with ink text.
        case neutral
        /// `surfaceSunken` with muted text.
        case muted
        /// A 16% `success` wash with `success` text.
        case success
    }

    let title: String
    let tone: Tone
    let dot: Color?
    let uppercase: Bool

    public init(_ title: String, tone: Tone = .neutral, dot: Color? = nil, uppercase: Bool = false) {
        self.title = title
        self.tone = tone
        self.dot = dot
        self.uppercase = uppercase
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let dot {
                Circle().fill(dot).frame(width: 6, height: 6)
            }
            Text(title)
                .textCase(uppercase ? Text.Case.uppercase : nil)
                .tracking(uppercase ? 0.8 : 0)
        }
        .font(uppercase ? Font.caption2.weight(.bold) : Font.caption.weight(.semibold))
        .foregroundStyle(foreground)
        .lineLimit(1)
        .padding(.horizontal, Space.x2)
        .frame(minHeight: uppercase ? 20 : 22)
        .background(background, in: Capsule())
        .fixedSize()
    }

    private var foreground: Color {
        switch tone {
        case .brand: .track
        case .lane: .lane
        case .neutral: .ink
        case .muted: .inkMuted
        case .success: .success
        }
    }

    private var background: Color {
        switch tone {
        case .brand: .trackSoft
        case .lane: .laneSoft
        case .neutral, .muted: .surfaceSunken
        case .success: Color.success.opacity(0.16)
        }
    }
}
