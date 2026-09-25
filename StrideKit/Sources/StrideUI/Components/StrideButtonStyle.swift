import SwiftUI

/// Full-width 52pt capsule buttons. One primary per screen.
public struct StrideButtonStyle: ButtonStyle {
    public enum Kind: Sendable { case primary, secondary }

    let kind: Kind

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: Dimension.control)
            .padding(.horizontal, Space.x5)
            .foregroundStyle(kind == .primary ? Color.onTrack : Color.ink)
            .background {
                if kind == .primary {
                    Capsule().fill(Color.track)
                } else {
                    Capsule().strokeBorder(Color.lineStrong, lineWidth: 1.5)
                }
            }
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

public extension ButtonStyle where Self == StrideButtonStyle {
    static var stridePrimary: StrideButtonStyle { StrideButtonStyle(kind: .primary) }
    static var strideSecondary: StrideButtonStyle { StrideButtonStyle(kind: .secondary) }
}
