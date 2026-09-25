import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Progress: the shoes in rotation and how worn they are.
struct ShoesSection: View {
    @Query(filter: #Predicate<Shoe> { !$0.isRetired }, sort: \Shoe.createdAt) private var shoes: [Shoe]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.defaultShoeID) private var defaultShoeRaw = ""
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            SectionHeader(title: "Shoes", route: .shoes)
            if shoes.isEmpty {
                VStack(alignment: .leading, spacing: Space.x3) {
                    if Illustration.exists("emptyShoes") {
                        Illustration(name: "emptyShoes", contentMode: .fill)
                            .frame(height: 140)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    Label("Track your shoes", systemImage: "shoe.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ink)
                    Text("See how far each pair has gone and when it's time for a new one.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                    Button("Add shoe") { adding = true }
                        .buttonStyle(.strideSecondary)
                }
                .raisedCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shoes.prefix(3).enumerated()), id: \.element.id) { index, shoe in
                        if index > 0 { Divider().padding(.leading, 68) }
                        NavigationLink(value: shoe) {
                            ShoeRow(shoe: shoe, unit: unit, isDefault: shoe.id.uuidString == defaultShoeRaw)
                                .padding(.horizontal, Space.x4)
                                .padding(.vertical, Space.x3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            }
        }
        .sheet(isPresented: $adding) { ShoeEditorView(shoe: nil) }
    }
}

/// A shoe's icon in its color.
struct ShoeIcon: View {
    let shoe: Shoe
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: "shoe.fill")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(shoe.isRetired ? Color.inkMuted : shoe.color)
            .frame(width: size, height: size)
            .background((shoe.isRetired ? Color.inkMuted : shoe.color).opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Name, distance and wear.
struct ShoeRow: View {
    let shoe: Shoe
    let unit: UnitSystem
    let isDefault: Bool
    /// Off in lists, which draw their own disclosure indicator.
    var showsChevron = true

    var body: some View {
        HStack(spacing: Space.x3) {
            ShoeIcon(shoe: shoe)
            VStack(alignment: .leading, spacing: Space.x1) {
                HStack(spacing: Space.x2) {
                    Text(shoe.displayName).font(.headline).foregroundStyle(.ink).lineLimit(1)
                    if isDefault {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.lane)
                            .padding(.horizontal, Space.x2)
                            .padding(.vertical, 2)
                            .background(Color.laneSoft, in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                if !shoe.brand.isEmpty {
                    Text(shoe.brand).font(.caption).foregroundStyle(.inkMuted).lineLimit(1)
                }
                ProgressBar(progress: shoe.wear, tint: ShoeWear.tint(shoe), height: 6)
                    .padding(.vertical, 2)
                HStack {
                    Text("\(ShoeWear.distance(shoe.totalDistance, unit: unit)) of \(ShoeWear.distance(shoe.maxDistance, unit: unit)) \(unit.distanceSymbol)")
                        .monospacedDigit()
                        .foregroundStyle(.inkMuted)
                    Spacer()
                    if shoe.isWornOut, !shoe.isRetired {
                        Text(shoe.wear >= 1 ? "Replace now" : "Replace soon").foregroundStyle(.warning)
                    }
                }
                .font(.caption.weight(.medium))
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.inkMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

enum ShoeWear {
    /// Whole units: shoe distances are hundreds of kilometers.
    static func distance(_ meters: Double, unit: UnitSystem) -> String {
        Int((meters / unit.metersPerUnit).rounded()).formatted()
    }

    static func tint(_ shoe: Shoe) -> Color {
        if shoe.isRetired { return .inkMuted }
        if shoe.wear >= 1 { return .danger }
        if shoe.isWornOut { return .warning }
        return shoe.color
    }
}

/// All shoes, in rotation and retired.
struct ShoesView: View {
    @Query(sort: \Shoe.createdAt) private var shoes: [Shoe]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.defaultShoeID) private var defaultShoeRaw = ""
    @State private var adding = false

    var body: some View {
        let active = shoes.filter { !$0.isRetired }
        let retired = shoes.filter(\.isRetired)
        List {
            if shoes.isEmpty {
                IllustratedEmptyState(illustration: "emptyShoes", symbol: "shoe.fill", title: "No shoes yet",
                                      message: "Add your running shoes to see how far each pair has gone.") {
                    Button("Add shoe") { adding = true }
                        .buttonStyle(.stridePrimary)
                        .padding(.top, Space.x2)
                }
                .listRowBackground(Color.clear)
            }
            if !active.isEmpty {
                Section {
                    ForEach(active) { row($0) }
                } header: {
                    Text("In rotation")
                } footer: {
                    Text("New runs on iPhone, Apple Watch and added by hand use your default shoe. Change it here or on the Run tab.")
                }
            }
            if !retired.isEmpty {
                Section("Retired") {
                    ForEach(retired) { row($0) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surface)
        .navigationTitle("Shoes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add shoe", systemImage: "plus") { adding = true }
            }
        }
        .sheet(isPresented: $adding) { ShoeEditorView(shoe: nil) }
    }

    private func row(_ shoe: Shoe) -> some View {
        NavigationLink(value: shoe) {
            ShoeRow(shoe: shoe, unit: unit, isDefault: shoe.id.uuidString == defaultShoeRaw, showsChevron: false)
        }
        .listRowBackground(Color.surfaceRaised)
        .swipeActions(edge: .trailing) {
            Button(shoe.isRetired ? "Restore" : "Retire", systemImage: shoe.isRetired ? "arrow.uturn.backward" : "archivebox") {
                ShoeDefaults.setRetired(shoe, !shoe.isRetired)
            }
            .tint(shoe.isRetired ? .lane : .inkMuted)
        }
        .swipeActions(edge: .leading) {
            if !shoe.isRetired, shoe.id.uuidString != defaultShoeRaw {
                Button("Make default", systemImage: "star") { ShoeDefaults.set(shoe) }
                    .tint(.lane)
            }
        }
    }
}
