import SwiftUI

/// A decorative SF Symbol in a filled circle or rounded square, leading a row or a card:
/// permissions and the plan's next session (`.brand`), suggested challenges (`.lane`), the onboarding
/// feature list (`.raised`), Profile settings (`.sunken`, `.rounded`, 36pt), shoes and completed
/// challenges (`.tinted(color)`). Hidden from VoiceOver: the row's text says what it is.
public struct IconBadge: View {
    public struct Style: Sendable {
        let fill: Color
        let foreground: Color

        public init(fill: Color, foreground: Color) {
            self.fill = fill
            self.foreground = foreground
        }

        /// `trackSoft` with a `track` symbol.
        public static let brand = Style(fill: .trackSoft, foreground: .track)
        /// `laneSoft` with a `lane` symbol.
        public static let lane = Style(fill: .laneSoft, foreground: .lane)
        /// `surfaceRaised` with an ink symbol, on the plain screen background.
        public static let raised = Style(fill: .surfaceRaised, foreground: .ink)
        /// `surfaceSunken` with an ink symbol, inside a raised card.
        public static let sunken = Style(fill: .surfaceSunken, foreground: .ink)
        /// `surfaceSunken` with a muted symbol: shoes on the summary, ended challenges.
        public static let muted = Style(fill: .surfaceSunken, foreground: .inkMuted)

        /// A 16% wash of `color` with the symbol in it.
        public static func tinted(_ color: Color) -> Style {
            Style(fill: color.opacity(0.16), foreground: color)
        }
    }

    public enum Corner: Sendable {
        case circle
        /// A rounded square, radius about a quarter of the size (10pt at 36pt).
        case rounded
    }

    let systemImage: String
    let style: Style
    let size: CGFloat
    let corner: Corner

    public init(_ systemImage: String, style: Style = .brand, size: CGFloat = 40, corner: Corner = .circle) {
        self.systemImage = systemImage
        self.style = style
        self.size = size
        self.corner = corner
    }

    public var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: size * 0.45, weight: .medium))
            .foregroundStyle(style.foreground)
            .frame(width: size, height: size)
            .background(style.fill, in: backgroundShape)
            .accessibilityHidden(true)
    }

    private var backgroundShape: AnyShape {
        switch corner {
        case .circle: AnyShape(Circle())
        case .rounded: AnyShape(RoundedRectangle(cornerRadius: size * 0.28))
        }
    }
}
