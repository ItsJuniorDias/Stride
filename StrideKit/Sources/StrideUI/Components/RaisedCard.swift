import SwiftUI

public extension View {
    /// Content on a raised card: `space-4` padding, `surfaceRaised`, `radius-md`.
    func raisedCard(padding: CGFloat = Space.x4, fill: Color = .surfaceRaised) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(fill, in: RoundedRectangle(cornerRadius: Radius.md))
    }
}
