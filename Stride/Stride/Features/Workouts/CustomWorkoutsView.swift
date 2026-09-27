import Foundation
import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// The runner's own interval workouts, built with Stride Pro, and the presets. Both are on the Run tab
/// under Intervals and on Apple Watch. After Pro ends the runner's workouts stay listed, read-only,
/// and can still be deleted.
struct CustomWorkoutsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \CustomWorkout.createdAt) private var workouts: [CustomWorkout]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var editing: WorkoutEditorTarget?
    @State private var upsell: ProFeature?
    /// The runner's paces, for the estimates, with Stride Pro only.
    @State private var paces: TrainingPaces?

    private var isPro: Bool { ProStore.shared.isPro }

    var body: some View {
        // A plain list drawn as the app's 14 pt cards with full-width hairlines (as designed), keeping
        // swipe to delete; section headings are ordinary clear rows.
        List {
            if !isPro, !workouts.isEmpty {
                headerRow(top: Space.x2) { StepLegend() }
                ProUpsellRow(symbol: "repeat", title: "Run and change them again",
                             detail: "Your workouts are kept. Stride Pro runs and edits them.") { upsell = .workouts }
                    .listRowInsets(EdgeInsets(top: Space.x3, leading: Space.x4, bottom: Space.x3, trailing: Space.x4))
                    .listRowBackground(CardRowBackground(isFirst: true, isLast: true))
                    .listRowSeparator(.hidden)
            }

            headerRow(top: !isPro && !workouts.isEmpty ? Space.x5 : Space.x2) {
                VStack(alignment: .leading, spacing: Space.x5) {
                    if isPro || workouts.isEmpty {
                        StepLegend()
                    }
                    if workouts.isEmpty {
                        SectionHeading("Your workouts")
                    } else {
                        SectionHeading("Your workouts", caption: "Swipe a workout to delete it")
                    }
                }
            }
            if workouts.isEmpty {
                emptyRow
                    .listRowInsets(EdgeInsets(top: Space.x4, leading: Space.x4, bottom: Space.x4, trailing: Space.x4))
                    .listRowBackground(CardRowBackground(isFirst: true, isLast: true))
                    .listRowSeparator(.hidden)
            } else {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { index, workout in
                    row(workout)
                        .listRowBackground(CardRowBackground(isFirst: index == 0, isLast: index == workouts.count - 1))
                        .listRowSeparator(.hidden)
                }
            }

            headerRow(top: Space.x5) { SectionHeading("Presets") }
            ForEach(Array(IntervalPresets.all.enumerated()), id: \.element.id) { index, preset in
                presetRow(preset)
                    .listRowBackground(CardRowBackground(isFirst: index == 0, isLast: index == IntervalPresets.all.count - 1))
                    .listRowSeparator(.hidden)
            }
            Label("All of these are on Stride for Apple Watch too.", systemImage: "applewatch")
                .font(.footnote)
                .foregroundStyle(.inkMuted)
                .listRowInsets(EdgeInsets(top: Space.x3, leading: 0, bottom: Space.x5, trailing: 0))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.horizontal, Space.x4, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Color.surface)
        .navigationTitle("Workouts")
        .toolbar {
            if isPro {
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = .new } label: {
                        Label("New workout", systemImage: "plus")
                            .labelStyle(.titleAndIcon)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(Color.onTrack)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .tint(.track)
                }
            }
        }
        .sheet(item: $editing) { target in
            CustomWorkoutEditor(workout: target.workout, template: target.template)
        }
        .proPaywall($upsell)
        .task(id: "\(isPro)-\(workouts.count)") {
            paces = isPro ? PersonalPaces.current(in: context) : nil
        }
    }

    /// A section heading as a clear list row.
    private func headerRow<Content: View>(top: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        content()
            .listRowInsets(EdgeInsets(top: top, leading: 0, bottom: Space.x3, trailing: 0))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// No workouts yet: what they are and the way to build one, or to Stride Pro.
    private var emptyRow: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(alignment: .top, spacing: Space.x3) {
                IconBadge("repeat", style: .brand)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.x2) {
                        Text("Build your own workouts").font(.headline).foregroundStyle(.ink)
                        if !isPro { TagBadge("Pro") }
                    }
                    Text(isPro
                         ? "Repeats, recoveries and a target pace, your way. They're ready on the Run tab and on Apple Watch."
                         : "Repeats, recoveries and a target pace, your way, with Stride Pro.")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Button(isPro ? "Build a workout" : "See Stride Pro") {
                if isPro { editing = .new } else { upsell = .workouts }
            }
            .buttonStyle(.strideSecondary)
        }
    }

    private func row(_ workout: CustomWorkout) -> some View {
        Button {
            if isPro { editing = .edit(workout) } else { upsell = .workouts }
        } label: {
            WorkoutListRow(title: workout.displayName, detail: detail(workout), steps: workout.steps, paces: paces, unit: unit)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: Space.x3, leading: Space.x4, bottom: Space.x3, trailing: Space.x4))
        .accessibilityHint(isPro ? "Edits the workout" : "Needs Stride Pro to edit")
        // The runner's own data: deleting never needs Pro.
        .swipeActions {
            Button("Delete", systemImage: "trash", role: .destructive) { delete(workout) }
        }
    }

    /// A preset opens the builder shaped like it, to save as the runner's own. The pyramid's runs
    /// differ in length, which the builder can't make, so it only shows.
    @ViewBuilder
    private func presetRow(_ preset: Workout) -> some View {
        let canCopy = WorkoutBlueprint(steps: preset.steps) != nil
        let label = WorkoutListRow(title: preset.name, detail: preset.detail, steps: preset.steps, paces: paces, unit: unit,
                                   showsChevron: canCopy)
        Group {
            if canCopy {
                Button {
                    if isPro { editing = .preset(preset) } else { upsell = .workouts }
                } label: {
                    label
                }
                .buttonStyle(.plain)
                .accessibilityHint(isPro ? "Starts a new workout from it" : "Needs Stride Pro to make your own")
            } else {
                label
            }
        }
        .listRowInsets(EdgeInsets(top: Space.x3, leading: Space.x4, bottom: Space.x3, trailing: Space.x4))
    }

    /// "800 m at 4'45" /km, 90 s recoveries", with the number of repeats when the name doesn't say it.
    private func detail(_ workout: CustomWorkout) -> String {
        guard let blueprint = workout.blueprint else { return "\(workout.steps.count) steps" }
        let defaultName = blueprint.defaultName(unit: unit)
        var text = workout.displayName == defaultName || blueprint.repeats == 1
            ? WorkoutBlueprint.text(for: blueprint.work, unit: unit)
            : defaultName
        if let pace = blueprint.workPace {
            text += " at \(RunFormat.pace(TrainingPaces.perUnit(pace, unit: unit))) \(unit.paceSymbol)"
        }
        if blueprint.repeats > 1, let recovery = blueprint.recovery {
            text += ", \(WorkoutBlueprint.text(for: recovery, unit: unit)) recoveries"
        }
        return text
    }

    private func delete(_ workout: CustomWorkout) {
        context.delete(workout)
        try? context.save()
        // The Watch drops it from its list too.
        WatchSync.shared.pushSettings()
    }
}

/// A workout in a list: its name, about how long and far, the steps in words and its shape.
struct WorkoutListRow: View {
    let title: String
    let detail: String
    let steps: [WorkoutStep]
    let paces: TrainingPaces?
    let unit: UnitSystem
    var showsChevron = true

    var body: some View {
        let estimate = paces.map { WorkoutEstimate(steps: steps, paces: $0) } ?? WorkoutEstimate(steps: steps)
        let time = WorkoutLength.minutes(estimate.duration)
        let distance = "\(RunFormat.distance(estimate.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
        VStack(alignment: .leading, spacing: Space.x2) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(time)
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.ink)
                    Text("· \(distance)")
                        .font(.subheadline)
                        .monospacedDigit()
                        .foregroundStyle(.inkMuted)
                    if showsChevron {
                        DisclosureChevron()
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StepStrip(steps: steps, durations: estimate.stepDurations, height: 6)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("About \(time), \(distance). \(detail)")
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

/// One row's part of a raised card: rounded on the card's first and last rows, with a full-width
/// hairline above every row but the first.
private struct CardRowBackground: View {
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        UnevenRoundedRectangle(topLeadingRadius: isFirst ? Radius.md : 0, bottomLeadingRadius: isLast ? Radius.md : 0,
                               bottomTrailingRadius: isLast ? Radius.md : 0, topTrailingRadius: isFirst ? Radius.md : 0,
                               style: .continuous)
            .fill(Color.surfaceRaised)
            .overlay(alignment: .top) {
                if !isFirst { Hairline() }
            }
    }
}
