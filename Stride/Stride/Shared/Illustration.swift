import SwiftUI
import UIKit
import StrideKit
import StrideUI

/// Artwork from the asset catalog (made with Tools/imagegen). Decorative, so VoiceOver skips it;
/// shows nothing when the image isn't in the catalog yet.
struct Illustration: View {
    let name: String
    var contentMode: ContentMode = .fit

    static func exists(_ name: String) -> Bool { UIImage(named: name) != nil }

    var body: some View {
        if let image = UIImage(named: name) {
            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .accessibilityHidden(true)
        }
    }
}

/// An empty state with artwork above the words: warmer than an SF Symbol for the first moments
/// in a screen. Falls back to the symbol when the artwork isn't available.
struct IllustratedEmptyState<Actions: View>: View {
    let illustration: String
    let symbol: String
    let title: String
    let message: String
    var imageHeight: CGFloat = 180
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Space.x3) {
            if Illustration.exists(illustration) {
                Illustration(name: illustration)
                    .frame(height: imageHeight)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .padding(.bottom, Space.x1)
            } else {
                Image(systemName: symbol)
                    .font(.largeTitle)
                    .foregroundStyle(.inkMuted)
                    .accessibilityHidden(true)
            }
            Text(title).font(.headline).foregroundStyle(.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .multilineTextAlignment(.center)
            actions
        }
        .frame(maxWidth: .infinity)
        .padding(Space.x4)
    }
}

extension TrainingPlan {
    /// The plan's cover in the asset catalog.
    var coverImage: String {
        switch id {
        case "first-5k": "planFirst5k"
        case "10k": "plan10k"
        case "half": "planHalfMarathon"
        default: ""
        }
    }
}
