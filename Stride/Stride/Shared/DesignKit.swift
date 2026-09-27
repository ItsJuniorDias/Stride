import SwiftUI
import StrideKit
import StrideUI

// App-level pieces of the design system: the ones that need the asset catalog or app types.
// Platform-neutral components live in StrideUI (see its DesignSystemGallery).

/// Artwork from the asset catalog cropped to fill a rounded frame: row thumbnails (64 × 64), plan
/// covers in lists (104 × 58), record, challenge and shoe art, and full-width banners (`width: nil`).
/// A sunken placeholder holds the shape while an image isn't in the catalog. Decorative.
struct ArtThumbnail: View {
    let name: String
    /// Nil fills the width offered.
    var width: CGFloat? = 64
    var height: CGFloat = 64
    var cornerRadius: CGFloat = Radius.sm

    var body: some View {
        Color.surfaceSunken
            .frame(width: width, height: height)
            .overlay {
                Illustration(name: name, contentMode: .fill)
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .accessibilityHidden(true)
    }
}

/// A shoe and how far it has gone: name, "412 of 700 km" and a wear bar in the shoe's color,
/// `warning` from 90% of its life and `danger` past it. On the run summary (40pt icon), the run
/// detail (36pt icon, 17pt name, 4pt bar, chevron) and the Progress shoes card (no icon).
struct ShoeWearRow: View {
    let shoe: Shoe
    let unit: UnitSystem
    var showsIcon = true
    var iconSize: CGFloat = 40
    var titleFont: Font = .subheadline.weight(.semibold)
    var barHeight: CGFloat = 6
    var showsChevron = false

    var body: some View {
        HStack(spacing: Space.x3) {
            if showsIcon {
                IconBadge("shoe", style: .muted, size: iconSize)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                    Text(shoe.displayName)
                        .font(titleFont)
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                    Spacer(minLength: Space.x2)
                    Text(distanceText)
                        .font(.footnote.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(.inkMuted)
                        .lineLimit(1)
                }
                TrackBar(progress: shoe.wear, tint: tint, height: barHeight)
            }
            if showsChevron {
                DisclosureChevron()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Shoe: \(shoe.displayName), \(distanceText)")
    }

    /// "412 of 700 km", whole units: shoe distances are hundreds of kilometers.
    private var distanceText: String {
        "\(Self.whole(shoe.totalDistance, unit: unit)) of \(Self.whole(shoe.maxDistance, unit: unit)) \(unit.distanceSymbol)"
    }

    private var tint: Color {
        if shoe.wear >= 1 { return .danger }
        if shoe.isWornOut { return .warning }
        return shoe.color
    }

    private static func whole(_ meters: Double, unit: UnitSystem) -> String {
        Int((meters / unit.metersPerUnit).rounded()).formatted()
    }
}
