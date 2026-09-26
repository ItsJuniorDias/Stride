import Foundation
import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// The runner's own interval workouts, built with Stride Pro. They're on the Run tab under Intervals
/// and on Apple Watch. After Pro ends they stay listed, read-only, and can still be deleted.
struct CustomWorkoutsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomWorkout.createdAt) private var workouts: [CustomWorkout]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var editing: WorkoutEditorTarget?
    @State private var upsell: ProFeature?

    private var isPro: Bool { ProStore.shared.isPro }

    var body: some View {
        List {
            if workouts.isEmpty {
                IllustratedEmptyState(illustration: "emptyWorkouts", symbol: "repeat", title: "Build your own workouts",
                                      message: isPro
                                          ? "Repeats, recoveries and a target pace, your way. They're ready on the Run tab and on Apple Watch."
                                          : "Repeats, recoveries and a target pace, your way, with Stride Pro.") {
                    Button(isPro ? "Build a workout" : "See Stride Pro") {
                        if isPro { editing = .new } else { upsell = .workouts }
                    }
                    .buttonStyle(.stridePrimary)
                    .padding(.top, Space.x2)
                }
                .listRowBackground(Color.clear)
            } else {
                if !isPro {
                    Section {
                        ProUpsellRow(symbol: "repeat", title: "Run and change them again",
                                     detail: "Your workouts are kept. Stride Pro runs and edits them.") { upsell = .workouts }
                    }
                    .listRowBackground(Color.surfaceRaised)
                }
                Section {
                    ForEach(workouts) { workout in
                        row(workout)
                    }
                } footer: {
                    Text("Pick one on the Run tab under Intervals, or start it on Apple Watch.")
                }
                .listRowBackground(Color.surfaceRaised)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surface)
        .navigationTitle("Your workouts")
        .toolbar {
            if isPro {
                ToolbarItem(placement: .primaryAction) {
                    Button("New workout", systemImage: "plus") { editing = .new }
                }
            }
        }
        .sheet(item: $editing) { target in
            CustomWorkoutEditor(workout: target.workout)
        }
        .proPaywall($upsell)
    }

    private func row(_ workout: CustomWorkout) -> some View {
        Button {
            if isPro { editing = .edit(workout) } else { upsell = .workouts }
        } label: {
            CustomWorkoutRow(workout: workout, unit: unit)
        }
        .buttonStyle(.plain)
        .accessibilityHint(isPro ? "Edits the workout" : "Needs Stride Pro to edit")
        // The runner's own data: deleting never needs Pro.
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { delete(workout) }
        }
    }

    private func delete(_ workout: CustomWorkout) {
        context.delete(workout)
        try? context.save()
        // The Watch drops it from its list too.
        WatchSync.shared.pushSettings()
    }
}

/// A custom workout's name, rough length, steps in words and its shape.
struct CustomWorkoutRow: View {
    let workout: CustomWorkout
    let unit: UnitSystem

    var body: some View {
        let steps = workout.steps
        let estimate = WorkoutEstimate(steps: steps)
        let detail = WorkoutBlueprint(steps: steps)?.detail(unit: unit) ?? "\(steps.count) steps"
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                Text(workout.displayName)
                    .font(.headline)
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                Spacer(minLength: Space.x2)
                Text(WorkoutLength.duration(estimate.duration, exact: estimate.isDurationExact))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.inkMuted)
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            WorkoutShapeBar(steps: steps, durations: estimate.stepDurations, height: 8)
                .padding(.top, 2)
        }
        .padding(.vertical, Space.x1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension CustomWorkout {
    /// The runner's workouts that can run, newest first, in the unit set in Profile: the ones Apple
    /// Watch lists after the presets (see ``WatchWorkoutLibrary``).
    static func forWatch(in context: ModelContext?) -> [Workout] {
        guard let context else { return [] }
        let unit = UnitSystem(rawValue: UserDefaults.standard.string(forKey: StrideSettings.unitSystem) ?? "") ?? .metric
        let descriptor = FetchDescriptor<CustomWorkout>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return ((try? context.fetch(descriptor)) ?? []).filter(\.isRunnable).map { $0.workout(unit: unit) }
    }
}
