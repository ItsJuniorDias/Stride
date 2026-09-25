import SwiftUI
import SwiftData
import StrideKit
import StrideUI

struct ActivitiesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var path: [Run] = []

    private var months: [(month: Date, runs: [Run])] {
        let calendar = Calendar.current
        return Dictionary(grouping: runs) { calendar.dateInterval(of: .month, for: $0.startDate)?.start ?? $0.startDate }
            .sorted { $0.key > $1.key }
            .map { (month: $0.key, runs: $0.value) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if runs.isEmpty {
                    ContentUnavailableView(
                        "No runs yet",
                        systemImage: "figure.run",
                        description: Text("Your runs will show up here after you finish one.")
                    )
                } else {
                    List {
                        ForEach(months, id: \.month) { group in
                            Section {
                                ForEach(group.runs) { run in
                                    NavigationLink(value: run) {
                                        RunRow(run: run, unit: unit)
                                    }
                                    .listRowBackground(Color.surfaceRaised)
                                }
                                .onDelete { offsets in
                                    for index in offsets { context.delete(group.runs[index]) }
                                    try? context.save()
                                }
                            } header: {
                                MonthHeader(month: group.month, runs: group.runs, unit: unit)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surface)
            .navigationTitle("Activities")
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
        }
        .onChange(of: runs) { path.removeAll { $0.isDeleted || $0.modelContext == nil } }
    }
}

private struct MonthHeader: View {
    let month: Date
    let runs: [Run]
    let unit: UnitSystem

    var body: some View {
        let total = runs.reduce(0) { $0 + $1.distance }
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year()))
            Spacer()
            Text("\(runs.count) \(runs.count == 1 ? "run" : "runs") · \(RunFormat.distance(total, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)")
                .monospacedDigit()
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.inkMuted)
        .textCase(nil)
    }
}
