import SwiftUI

/// A 44pt round button floating over a map or artwork (centre on location, share, add): Liquid
/// Glass on iOS 26 and later, a material circle with a hairline edge and the panel shadow before
/// that. The button shows only a symbol, so the accessibility label is required.
public struct GlassIconButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let tint: Color
    let action: () -> Void

    public init(_ systemImage: String, accessibilityLabel: String, tint: Color = .ink, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                .floatingGlass(in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

/// A text button on a 44pt glass capsule, for the top of a map ("Edit").
public struct GlassCapsuleButton: View {
    let title: String
    let systemImage: String?
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .accessibilityHidden(true)
                }
                Text(title)
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(.ink)
            .padding(.horizontal, 18)
            .frame(minHeight: Dimension.hitMin)
            .floatingGlass(in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(PressScaleButtonStyle())
    }
}

public extension View {
    /// Interactive Liquid Glass in `shape`, for small controls and legends floating over maps and
    /// artwork. Before iOS 26: a material with a hairline edge and the panel shadow. Cards on plain
    /// surfaces stay flat and don't use this.
    @ViewBuilder
    func floatingGlass<S: Shape>(in shape: S, interactive: Bool = true) -> some View {
        if #available(iOS 26, watchOS 26, *) {
            glassEffect(.regular.interactive(interactive), in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay { shape.stroke(Color.white.opacity(0.08), lineWidth: 1) }
                .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
        }
    }
}

/// A round icon button on a plain surface: map and lock on the live run (`.raised`), steppers in
/// cards (`.sunken`, 32pt) and onboarding (`.outlined`, 48pt), and the Apple Watch controls, which
/// pass a `title` shown under the circle. The tap area is never smaller than 44pt. For buttons over
/// a map, use ``GlassIconButton``.
public struct RoundIconButton: View {
    public enum Style: Sendable {
        /// `surfaceRaised` circle, ink symbol.
        case raised
        /// `surfaceSunken` circle, ink symbol.
        case sunken
        /// 1.5pt `lineStrong` ring, ink symbol.
        case outlined
        /// A solid circle, e.g. `.track` for Pause on the watch, with an `onTrack` symbol.
        case filled(Color)
        /// A 16% wash of the color with the symbol in it, e.g. `.danger` for End.
        case tinted(Color)
    }

    let systemImage: String
    let accessibilityLabel: String
    let style: Style
    let diameter: CGFloat
    let title: String?
    let action: () -> Void

    public init(_ systemImage: String, accessibilityLabel: String, style: Style = .raised,
                diameter: CGFloat = Dimension.hitMin, title: String? = nil, action: @escaping () -> Void) {
        self.systemImage = systemImage
        self.accessibilityLabel = accessibilityLabel
        self.style = style
        self.diameter = diameter
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(spacing: Space.x1) {
                RoundIconFace(systemImage: systemImage, style: style, diameter: diameter)
                    .frame(width: max(diameter, Dimension.hitMin), height: max(diameter, Dimension.hitMin))
                    .contentShape(Rectangle())
                if let title {
                    Text(title)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.inkMuted)
                }
            }
        }
        .buttonStyle(PressScaleButtonStyle())
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct RoundIconFace: View {
    let systemImage: String
    let style: RoundIconButton.Style
    let diameter: CGFloat
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: max(diameter * 0.42, 15), weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: diameter, height: diameter)
            .background { background }
            .opacity(isEnabled ? 1 : 0.4)
    }

    private var foreground: Color {
        switch style {
        case .raised, .sunken, .outlined: .ink
        case .filled: .onTrack
        case .tinted(let color): color
        }
    }

    @ViewBuilder private var background: some View {
        switch style {
        case .raised: Circle().fill(Color.surfaceRaised)
        case .sunken: Circle().fill(Color.surfaceSunken)
        case .outlined: Circle().strokeBorder(Color.lineStrong, lineWidth: 1.5)
        case .filled(let color): Circle().fill(color)
        case .tinted(let color): Circle().fill(color.opacity(0.16))
        }
    }
}
