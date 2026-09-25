import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// One shoe: its distance and wear, the default and retire controls, and the runs it did.
struct ShoeDetailView: View {
    let shoe: Shoe
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.defaultShoeID) private var defaultShoeRaw = ""
    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        if shoe.isDeleted || shoe.modelContext == nil {
            ContentUnavailableView("Shoe deleted", systemImage: "trash")
        } else {
            content
        }
    }

    private var isDefault: Bool { shoe.id.uuidString == defaultShoeRaw }

    private var content: some View {
        let runs = (shoe.runs ?? []).sorted { $0.startDate > $1.startDate }
        let totals = RunTotals(runs.map(\.sample))
        return ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                VStack(alignment: .leading, spacing: Space.x4) {
                    HStack(spacing: Space.x3) {
                        ShoeIcon(shoe: shoe, size: 56)
                        VStack(alignment: .leading, spacing: 2) {
                            if !shoe.brand.isEmpty {
                                Text(shoe.brand).font(.subheadline).foregroundStyle(.inkMuted)
                            }
                            HStack(spacing: Space.x2) {
                                if isDefault { StatusChip("Default", indicator: .lane, background: .laneSoft) }
                                if shoe.isRetired { StatusChip("Retired", indicator: .inkMuted, background: .surfaceSunken) }
                            }
                        }
                    }
                    MetricView("Distance", value: ShoeWear.distance(shoe.totalDistance, unit: unit),
                               unit: "of \(ShoeWear.distance(shoe.maxDistance, unit: unit)) \(unit.distanceSymbol)", size: .large)
                    ProgressBar(progress: shoe.wear, tint: ShoeWear.tint(shoe), height: 10)
                    Text(wearText)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(shoe.isWornOut && !shoe.isRetired ? Color.warning : Color.inkMuted)
                }
                .raisedCard()

                Grid(horizontalSpacing: Space.x3, verticalSpacing: Space.x3) {
                    GridRow {
                        MetricTile("Runs", value: "\(totals.runs)")
                        MetricTile("Time", value: totalTime(totals.duration))
                    }
                    GridRow {
                        MetricTile("Avg pace", value: RunFormat.pace(totals.averagePace(in: unit)), unit: unit.paceSymbol)
                        MetricTile("Last run", value: runs.first.map { shortDate($0.startDate) } ?? RunFormat.empty)
                    }
                }

                VStack(spacing: Space.x3) {
                    if !shoe.isRetired, !isDefault {
                        Button("Make default") { ShoeDefaults.set(shoe) }
                            .buttonStyle(.strideSecondary)
                    }
                    Button(shoe.isRetired ? "Put back in rotation" : "Retire shoe") {
                        ShoeDefaults.setRetired(shoe, !shoe.isRetired)
                    }
                    .buttonStyle(.strideSecondary)
                }

                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("Runs").font(.headline).foregroundStyle(.ink)
                    if runs.isEmpty {
                        Text("No runs in these shoes yet.")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                            .raisedCard()
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                                if index > 0 { Divider().padding(.leading, Space.x4) }
                                NavigationLink(value: run) {
                                    RunRow(run: run, unit: unit)
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
            }
            .padding(Space.x4)
        }
        .background(Color.surface)
        .navigationTitle(shoe.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { editing = true }
                    Button("Delete Shoe", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $editing) { ShoeEditorView(shoe: shoe) }
        .confirmationDialog("Delete \(shoe.displayName)?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Shoe", role: .destructive) {
                let shoe = self.shoe
                if isDefault { ShoeDefaults.set(nil) }
                dismiss()
                // Delete after the pop so this screen never renders a deleted model.
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    context.delete(shoe)
                    try? context.save()
                }
            }
        } message: {
            Text("Its runs stay, without a shoe. To keep its history, retire it instead.")
        }
    }

    private var wearText: String {
        if shoe.isRetired { return "Retired after \(ShoeWear.distance(shoe.totalDistance, unit: unit)) \(unit.distanceSymbol)" }
        let remaining = shoe.remainingDistance
        if remaining <= 0 {
            return "\(ShoeWear.distance(-remaining, unit: unit)) \(unit.distanceSymbol) past its replacement distance"
        }
        return "\(ShoeWear.distance(remaining, unit: unit)) \(unit.distanceSymbol) left before replacing"
    }
}
