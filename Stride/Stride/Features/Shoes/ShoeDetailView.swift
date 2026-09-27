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
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.x3) {
                        ShoeIcon(shoe: shoe, size: 44)
                        VStack(alignment: .leading, spacing: 2) {
                            if !shoe.brand.isEmpty {
                                Text(shoe.brand).font(.subheadline).foregroundStyle(.inkMuted)
                            }
                            if isDefault || shoe.isRetired {
                                HStack(spacing: Space.x2) {
                                    if isDefault { SoftBadge("Default", tone: .lane) }
                                    if shoe.isRetired { SoftBadge("Retired", tone: .muted) }
                                }
                            }
                        }
                    }
                    StatTile("Distance", value: ShoeWear.distance(shoe.totalDistance, unit: unit),
                             unit: "of \(ShoeWear.distance(shoe.maxDistance, unit: unit)) \(unit.distanceSymbol)", size: .large)
                        .padding(.top, Space.x4)
                    TrackBar(progress: shoe.wear, tint: ShoeWear.tint(shoe), height: 10, band: shoe.isRetired ? nil : 0.9...1)
                        .padding(.top, Space.x3)
                    Text(ShoeWear.status(shoe, unit: unit))
                        .font(.footnote)
                        .foregroundStyle(ShoeWear.isDue(shoe) ? Color.warning : Color.inkMuted)
                        .padding(.top, Space.x2)
                }
                .raisedCard()

                DividedGrid(columns: 2) {
                    StatTile("Runs", value: "\(totals.runs)", size: .medium)
                    StatTile("Time", value: totalTime(totals.duration), size: .medium)
                    StatTile("Avg pace", value: RunFormat.pace(totals.averagePace(in: unit)), unit: unit.paceSymbol, size: .medium)
                    StatTile("Last run", value: runs.first.map { shortDate($0.startDate) } ?? RunFormat.empty, size: .medium)
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
                    SectionHeading("Runs", detail: runs.isEmpty ? nil : "\(runs.count)")
                    if runs.isEmpty {
                        Text("No runs in these shoes yet.")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                            .raisedCard()
                    } else {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(runs.enumerated()), id: \.element.id) { index, run in
                                if index > 0 { Hairline(leadingInset: 84) }
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
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
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
}
