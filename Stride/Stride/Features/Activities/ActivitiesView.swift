import SwiftUI
import SwiftData
import StrideKit
import StrideUI

struct ActivitiesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    /// Mixed routes (runs and shoes); a deleted run's screen shows its own "Run deleted" state.
    @State private var path = NavigationPath()
    @State private var addingRun = false

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
                    ScrollView {
                        IllustratedEmptyState(illustration: "emptyActivities", symbol: "figure.run", title: "No runs yet",
                                              message: "Your runs will show up here after you finish one.") {
                            Button("Add a run manually") { addingRun = true }
                                .buttonStyle(.strideSecondary)
                                .fixedSize()
                                .padding(.top, Space.x2)
                        }
                        .padding(.top, Space.x6)
                    }
                    .background(Color.surface)
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
                                    for index in offsets {
                                        HealthSync.shared.delete(workoutID: group.runs[index].healthWorkoutID)
                                        Vitals.delete(group.runs[index], in: context)
                                    }
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addingRun = true } label: {
                        Label("Add run", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $addingRun) { ManualRunView() }
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
            .progressDestinations()
        }
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
