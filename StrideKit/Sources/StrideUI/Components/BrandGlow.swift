import SwiftUI

/// The soft brand light behind a moment screen, drawn from `track` (and `lane` for `.blobs`), so it
/// works in both themes. Decorative and untouchable; put it in a background and let it run under
/// the safe areas:
///
///     .background { BrandGlow(.spotlight).ignoresSafeArea() }
public struct BrandGlow: View {
    public enum Style: Sendable {
        /// Two blurred blobs low on the screen, brand on the left and data color on the right:
        /// onboarding's welcome page.
        case blobs
        /// A brand glow off the top-leading corner: the run summary. Put it in the scroll content so
        /// it scrolls away.
        case corner
        /// A radial glow in the upper middle, from the brand color through `trackSoft` to the
        /// background: the countdown.
        case spotlight
        /// A `trackSoft` wash fading down from the top 300pt: the paused live run.
        case wash
    }

    let style: Style
    @Environment(\.colorScheme) private var colorScheme

    public init(_ style: Style) {
        self.style = style
    }

    public var body: some View {
        GeometryReader { geo in
            glow(in: geo.size)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private func glow(in size: CGSize) -> some View {
        let dark = colorScheme == .dark
        switch style {
        case .blobs:
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Color.track)
                    .frame(width: 280, height: 280)
                    .opacity(dark ? 0.16 : 0.12)
                    .blur(radius: 80)
                    .offset(x: -90, y: size.height * 0.56)
                Circle()
                    .fill(Color.lane)
                    .frame(width: 220, height: 220)
                    .opacity(dark ? 0.12 : 0.09)
                    .blur(radius: 80)
                    .offset(x: size.width - 140, y: size.height * 0.66)
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
        case .corner:
            EllipticalGradient(colors: [Color.track.opacity(dark ? 0.2 : 0.14), Color.track.opacity(0)],
                               center: .center, startRadiusFraction: 0, endRadiusFraction: 0.5)
                .frame(width: 420, height: 380)
                .offset(x: -80, y: -120)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
        case .spotlight:
            let center = UnitPoint(x: 0.5, y: 0.42)
            let reach = hypot(max(center.x, 1 - center.x) * size.width, max(center.y, 1 - center.y) * size.height)
            RadialGradient(stops: [
                .init(color: Color.track.opacity(dark ? 0.32 : 0.22), location: 0),
                .init(color: Color.trackSoft, location: 0.36),
                .init(color: Color.surface, location: 0.76),
            ], center: center, startRadius: 0, endRadius: max(reach, 1))
        case .wash:
            LinearGradient(colors: [Color.trackSoft.opacity(0.75), Color.trackSoft.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 300)
                .frame(width: size.width, height: size.height, alignment: .top)
        }
    }
}
