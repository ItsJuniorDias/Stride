import SwiftUI

public extension View {
    /// A panel floating over the map: Liquid Glass on iOS 26 and later, a thick material with the
    /// `shadow-panel` shadow before that. Cards on plain surfaces stay flat and don't use this.
    @ViewBuilder
    func glassPanel(cornerRadius: CGFloat = Radius.lg) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(iOS 26, watchOS 26, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .shadow(color: .black.opacity(0.14), radius: 16, y: 8)
        }
    }
}
