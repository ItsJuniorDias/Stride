import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Every run, newest first, a card per month under the month's name, run count and total distance.
/// Swipe a run to delete it; the plus adds one by hand.
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
                    runList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surface)
            .navigationTitle("Activities")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Add a run", systemImage: "plus") { addingRun = true }
                }
            }
            .sheet(isPresented: $addingRun) { ManualRunView() }
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
            .progressDestinations()
        }
    }

    /// A `List` for swipe to delete, drawn as the design's cards: each month's rows share one raised
    /// card with hairlines inset past the thumbnail.
    private var runList: some View {
        let groups = months
        return List {
            ForEach(Array(groups.enumerated()), id: \.element.month) { index, group in
                Section {
                    MonthHeader(month: group.month, runs: group.runs, unit: unit)
                        .listRowInsets(EdgeInsets(top: index == 0 ? Space.x2 : 28, leading: Space.x4,
                                                  bottom: Space.x3, trailing: Space.x4))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)

                    ForEach(Array(group.runs.enumerated()), id: \.element.id) { position, run in
                        let isFirst = position == 0
                        let isLast = position == group.runs.count - 1
                        Button {
                            path.append(run)
                        } label: {
                            RunRow(run: run, unit: unit, showsChevron: true)
                                .padding(.leading, Space.x3)
                                .padding(.trailing, 14)
                                .padding(.vertical, 11)
                                .overlay(alignment: .bottom) {
                                    if !isLast { Hairline(leadingInset: 80) }
                                }
                        }
                        .buttonStyle(MonthCardRowStyle(isFirst: isFirst, isLast: isLast))
                        .listRowInsets(EdgeInsets(top: 0, leading: Space.x4, bottom: 0, trailing: Space.x4))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            HealthSync.shared.delete(workoutID: group.runs[index].healthWorkoutID)
                            Vitals.delete(group.runs[index], in: context)
                        }
                        try? context.save()
                    }
                }
                .listSectionSeparator(.hidden)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.bottom, Space.x5, for: .scrollContent)
    }
}

/// "September / 2026 · 12 runs" with the month's total distance on the right.
private struct MonthHeader: View {
    let month: Date
    let runs: [Run]
    let unit: UnitSystem

    var body: some View {
        let total = runs.reduce(0) { $0 + $1.distance }
        let count = "\(runs.count) \(runs.count == 1 ? "run" : "runs")"
        HStack(alignment: .bottom, spacing: Space.x3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(month.formatted(.dateTime.month(.wide)))
                    .font(.title2.bold())
                    .foregroundStyle(.ink)
                Text("\(month.formatted(.dateTime.year())) · \(count)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.inkMuted)
            }
            Spacer(minLength: Space.x2)
            VStack(alignment: .trailing, spacing: 2) {
                Text("Total").metricLabelStyle()
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(RunFormat.distance(total, unit: unit, fractionDigits: 1))
                        .font(.metricSmall)
                        .monospacedDigit()
                        .foregroundStyle(.ink)
                    Text(unit.distanceSymbol)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.inkMuted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(month.formatted(.dateTime.month(.wide).year())), \(count), \(CoachScript.spokenDistance(total, unit: unit)) in total")
        .accessibilityAddTraits(.isHeader)
    }
}

/// A row of a month's card: the raised fill, rounded on the first and last rows, and a sunken
/// fill while pressed.
private struct MonthCardRowStyle: ButtonStyle {
    let isFirst: Bool
    let isLast: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = UnevenRoundedRectangle(topLeadingRadius: isFirst ? Radius.md : 0,
                                           bottomLeadingRadius: isLast ? Radius.md : 0,
                                           bottomTrailingRadius: isLast ? Radius.md : 0,
                                           topTrailingRadius: isFirst ? Radius.md : 0)
        return configuration.label
            .background(configuration.isPressed ? Color.surfaceSunken : Color.surfaceRaised, in: shape)
            .clipShape(shape)
            .contentShape(shape)
    }
}
