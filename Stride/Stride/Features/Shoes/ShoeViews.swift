import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// A shoe's symbol in a soft circle of its color; muted once retired.
struct ShoeIcon: View {
    let shoe: Shoe
    var size: CGFloat = 40

    var body: some View {
        IconBadge("shoe", style: .tinted(shoe.isRetired ? .inkMuted : shoe.color), size: size)
    }
}

enum ShoeWear {
    /// Whole units: shoe distances are hundreds of kilometers.
    static func distance(_ meters: Double, unit: UnitSystem) -> String {
        Int((meters / unit.metersPerUnit).rounded()).formatted()
    }

    /// The wear bar: the shoe's color, `warning` from 90% of its life, `danger` past it.
    static func tint(_ shoe: Shoe) -> Color {
        if shoe.isRetired { return .inkMuted }
        if shoe.wear >= 1 { return .danger }
        if shoe.isWornOut { return .warning }
        return shoe.color
    }

    /// Due for replacing and still in rotation.
    static func isDue(_ shoe: Shoe) -> Bool {
        shoe.isWornOut && !shoe.isRetired
    }

    /// "288 km left before replacing", "42 km left · replace soon", "12 km past its replacement
    /// distance", "Retired after 731 km".
    static func status(_ shoe: Shoe, unit: UnitSystem) -> String {
        let symbol = unit.distanceSymbol
        if shoe.isRetired { return "Retired after \(distance(shoe.totalDistance, unit: unit)) \(symbol)" }
        let remaining = shoe.remainingDistance
        if remaining <= 0 { return "\(distance(-remaining, unit: unit)) \(symbol) past its replacement distance" }
        if shoe.isWornOut { return "\(distance(remaining, unit: unit)) \(symbol) left · replace soon" }
        return "\(distance(remaining, unit: unit)) \(symbol) left before replacing"
    }
}

/// All shoes: a summary, the ones in rotation as cards, the retired ones, and Add shoe. A list, so
/// shoes can be swiped: retire or restore, and make default.
struct ShoesView: View {
    @Query(sort: \Shoe.createdAt) private var shoes: [Shoe]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.defaultShoeID) private var defaultShoeRaw = ""
    @State private var adding = false
    @State private var opened: Shoe?

    var body: some View {
        let active = shoes.filter { !$0.isRetired }
        let retired = shoes.filter(\.isRetired)
        List {
            if shoes.isEmpty {
                IllustratedEmptyState(illustration: "emptyShoes", symbol: "shoe", title: "No shoes yet",
                                      message: "Add your running shoes to see how far each pair has gone.") {
                    Button("Add shoe") { adding = true }
                        .buttonStyle(.stridePrimary)
                        .padding(.top, Space.x2)
                }
                .shoeListRow(top: Space.x2)
            } else {
                if !active.isEmpty {
                    summary(active)
                        .shoeListRow(top: Space.x4)
                    SectionHeading("In rotation", style: .overline)
                        .shoeListRow(top: Space.x5, bottom: Space.x2 - 6)
                    ForEach(active) { shoe in
                        activeCard(shoe)
                    }
                    Text("New runs on iPhone, Apple Watch and added by hand use your default shoe. Swipe a shoe to retire it.")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                        .padding(.horizontal, Space.x1)
                        .shoeListRow(top: Space.x2 - 6)
                }
                if !retired.isEmpty {
                    SectionHeading("Retired", style: .overline)
                        .shoeListRow(top: Space.x5, bottom: Space.x2 - 6)
                    ForEach(retired) { shoe in
                        retiredCard(shoe)
                    }
                }
                Button { adding = true } label: {
                    Label("Add shoe", systemImage: "plus")
                }
                .buttonStyle(.stridePrimary)
                .shoeListRow(top: Space.x5, bottom: Space.x5)
            }
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .scrollContentBackground(.hidden)
        .background(Color.surface)
        .navigationTitle("Shoes")
        .navigationBarTitleDisplayMode(.large)
        .navigationDestination(item: $opened) { ShoeDetailView(shoe: $0) }
        .sheet(isPresented: $adding) { ShoeEditorView(shoe: nil) }
    }

    private func isDefault(_ shoe: Shoe) -> Bool {
        shoe.id.uuidString == defaultShoeRaw
    }

    /// "2 pairs in rotation · 508 km between them."
    private func summary(_ active: [Shoe]) -> some View {
        let total = ShoeWear.distance(active.reduce(0) { $0 + $1.totalDistance }, unit: unit)
        let symbol = unit.distanceSymbol
        let lifespan = unit == .metric ? "Most running shoes last 500–800 km." : "Most running shoes last 300–500 miles."
        return HStack(spacing: 14) {
            ArtThumbnail(name: "emptyShoes", width: 72, height: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(active.count == 1 ? "1 pair in rotation" : "\(active.count) pairs in rotation")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
                Text(active.count == 1 ? "\(total) \(symbol) on it. \(lifespan)" : "\(total) \(symbol) between them. \(lifespan)")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .raisedCard()
        .accessibilityElement(children: .combine)
    }

    private func activeCard(_ shoe: Shoe) -> some View {
        ShoeCard(shoe: shoe, unit: unit, isDefault: isDefault(shoe),
                 open: { opened = shoe },
                 makeDefault: { ShoeDefaults.set(shoe) })
            .shoeListRow(top: 6, bottom: 6)
            .swipeActions(edge: .trailing) {
                Button("Retire", systemImage: "archivebox") {
                    ShoeDefaults.setRetired(shoe, true)
                }
                .tint(.inkMuted)
            }
            .swipeActions(edge: .leading) {
                if !isDefault(shoe) {
                    Button("Make default", systemImage: "star") { ShoeDefaults.set(shoe) }
                        .tint(.lane)
                }
            }
    }

    private func retiredCard(_ shoe: Shoe) -> some View {
        Button {
            opened = shoe
        } label: {
            HStack(spacing: Space.x3) {
                ShoeIcon(shoe: shoe, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(shoe.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                    Text(ShoeWear.status(shoe, unit: unit))
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DisclosureChevron()
                    .frame(width: Dimension.hitMin, height: Dimension.hitMin)
            }
            .padding(EdgeInsets(top: 10, leading: Space.x4, bottom: 10, trailing: Space.x1))
            .frame(minHeight: 64)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .shoeListRow(top: 6, bottom: 6)
        .swipeActions(edge: .trailing) {
            Button("Restore", systemImage: "arrow.uturn.backward") {
                ShoeDefaults.setRetired(shoe, false)
            }
            .tint(.lane)
        }
    }
}

/// A shoe in rotation: its name and brand, distance against its replacement distance, a wear bar
/// with the replace-soon last 10%, what's left, and Make default. The card opens the shoe.
private struct ShoeCard: View {
    let shoe: Shoe
    let unit: UnitSystem
    let isDefault: Bool
    let open: () -> Void
    let makeDefault: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.x3) {
                    ShoeIcon(shoe: shoe, size: 44)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: Space.x2) {
                            Text(shoe.displayName)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.ink)
                                .lineLimit(1)
                            if isDefault {
                                SoftBadge("Default", tone: .lane)
                            }
                        }
                        if !shoe.brand.isEmpty, shoe.brand != shoe.displayName {
                            Text(shoe.brand)
                                .font(.footnote)
                                .foregroundStyle(.inkMuted)
                                .lineLimit(1)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    DisclosureChevron()
                        .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                        .padding(.trailing, -Space.x3)
                }
                HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                    Text(ShoeWear.distance(shoe.totalDistance, unit: unit))
                        .font(.system(size: 28, weight: .bold).width(.expanded))
                        .monospacedDigit()
                        .foregroundStyle(.ink)
                    Text("of \(ShoeWear.distance(shoe.maxDistance, unit: unit)) \(unit.distanceSymbol)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.inkMuted)
                }
                .padding(.top, Space.x3)
                TrackBar(progress: shoe.wear, tint: ShoeWear.tint(shoe), height: 8, band: 0.9...1)
                    .padding(.top, 10)
                Text(ShoeWear.status(shoe, unit: unit))
                    .font(.footnote)
                    .foregroundStyle(ShoeWear.isDue(shoe) ? Color.warning : Color.inkMuted)
                    .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                    // Room for Make default, drawn over the card.
                    .padding(.trailing, isDefault ? 0 : 112)
                    .padding(.top, Space.x2)
            }
            .padding(Space.x4)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isDefault ? "\(shoe.displayName), default shoe" : shoe.displayName)
        .accessibilityValue(accessibilityValue)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .overlay(alignment: .bottomTrailing) {
            if !isDefault {
                LinkButton("Make default", action: makeDefault)
                    .padding(.horizontal, Space.x1)
                    .padding(.trailing, Space.x3)
                    // Centered on the last line of the card.
                    .padding(.bottom, 3)
            }
        }
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if !shoe.brand.isEmpty, shoe.brand != shoe.displayName { parts.append(shoe.brand) }
        parts.append("\(ShoeWear.distance(shoe.totalDistance, unit: unit)) of \(ShoeWear.distance(shoe.maxDistance, unit: unit)) \(unit.distanceSymbol)")
        parts.append(ShoeWear.status(shoe, unit: unit))
        return parts.joined(separator: ", ")
    }
}

private extension View {
    /// A row of the shoes list drawn as the design's cards: no separator, no row background.
    func shoeListRow(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: Space.x4, bottom: bottom, trailing: Space.x4))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
