import Foundation
import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// What the builder sheet opens on: a new workout or one to edit.
enum WorkoutEditorTarget: Identifiable {
    case new
    case edit(CustomWorkout)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let workout): workout.id.uuidString
        }
    }

    var workout: CustomWorkout? {
        switch self {
        case .new: nil
        case .edit(let workout): workout
        }
    }
}

/// Builds or edits a custom workout (Stride Pro): a warm-up, repeats of a run with recoveries between
/// them, a cool-down, and the whole thing at a glance. Saved workouts are on the Run tab under
/// Intervals and on Apple Watch.
struct CustomWorkoutEditor: View {
    /// Nil for a new workout.
    let workout: CustomWorkout?
    /// After saving, e.g. to pick the workout on the Run tab.
    var onSave: (CustomWorkout) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    @State private var name = ""
    @State private var hasWarmup = true
    @State private var warmup = WorkoutBlueprint.starter.warmup ?? .time(600)
    @State private var repeats = WorkoutBlueprint.starter.repeats
    @State private var work = WorkoutBlueprint.starter.work
    /// Seconds per kilometer; nil for no target.
    @State private var workPace: Double?
    /// Kept while there's a single repeat, so going back to several brings it back.
    @State private var recovery = WorkoutBlueprint.starter.recovery ?? .time(120)
    @State private var hasCooldown = true
    @State private var cooldown = WorkoutBlueprint.starter.cooldown ?? .time(300)
    /// The runner's paces, for a suggested target and the estimate.
    @State private var paces: TrainingPaces?
    @State private var loaded = false
    /// False for steps a newer builder made: they run, but can't be changed here.
    @State private var isEditable = true
    @State private var confirmingDelete = false
    @State private var upsell: ProFeature?

    private var blueprint: WorkoutBlueprint {
        WorkoutBlueprint(warmup: hasWarmup ? warmup : nil, repeats: repeats, work: work, workPace: workPace,
                         recovery: recovery, cooldown: hasCooldown ? cooldown : nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if isEditable {
                    editor
                } else {
                    Section {
                        Text("This workout was made with a newer version of Stride. It runs as it is, but can't be changed here.")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }
                }
                if workout != nil {
                    Section {
                        Button("Delete workout", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle(workout == nil ? "New workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).disabled(!isEditable)
                }
            }
            .onAppear(perform: load)
            // After the sheet is up: reading every run's best efforts can take a moment.
            .task { paces = ProStore.shared.isPro ? PersonalPaces.current(in: context) : nil }
            .proPaywall($upsell)
            .confirmationDialog("Delete \(workout?.displayName ?? "workout")?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete Workout", role: .destructive, action: delete)
            } message: {
                Text("Runs you did with it stay in your history.")
            }
        }
    }

    @ViewBuilder private var editor: some View {
        Section {
            TextField("Name", text: $name, prompt: Text(blueprint.defaultName(unit: unit)))
                .onChange(of: name) { _, value in
                    if value.count > CustomWorkout.maxNameLength { name = String(value.prefix(CustomWorkout.maxNameLength)) }
                }
        }

        Section {
            Toggle("Warm-up", isOn: $hasWarmup.animation()).tint(.track)
            if hasWarmup {
                GoalPicker(title: "Length", goal: $warmup, role: .easy, unit: unit)
            }
        }

        Section {
            Stepper(value: $repeats.animation(), in: WorkoutBlueprint.repeatRange) {
                LabeledContent("Repeats", value: "\(repeats)")
            }
            GoalPicker(title: "Run", goal: $work, role: .work, unit: unit)
            targetPacePicker
            if let suggestion = suggestedPace {
                Button {
                    workPace = suggestion.perUnit * 1_000 / unit.metersPerUnit
                } label: {
                    Label("Use your \(suggestion.intensity.title.lowercased()) pace, \(RunFormat.pace(suggestion.perUnit)) \(unit.paceSymbol)",
                          systemImage: "gauge.with.needle")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.lane)
                }
            }
            if repeats > 1 {
                GoalPicker(title: "Recovery", goal: $recovery, role: .recovery, unit: unit)
            }
        } header: {
            Text("Repeats")
        } footer: {
            Text("The coach calls every step. With a target pace, it tells you when you drift more than 10 seconds off it.")
        }

        Section {
            Toggle("Cool-down", isOn: $hasCooldown.animation()).tint(.track)
            if hasCooldown {
                GoalPicker(title: "Length", goal: $cooldown, role: .easy, unit: unit)
            }
        }

        Section {
            WorkoutSummaryRows(steps: blueprint.steps, paces: paces, unit: unit)
        } header: {
            Text("Total")
        } footer: {
            Text(estimateFooter)
        }
    }

    /// Off, or a pace per the runner's unit; stored per kilometer like every step target.
    private var targetPacePicker: some View {
        let perUnit = Binding<Double>(
            get: { workPace.map { TrainingPaces.perUnit($0, unit: unit).rounded() } ?? 0 },
            set: { workPace = $0 > 0 ? $0 * 1_000 / unit.metersPerUnit : nil }
        )
        // Every 5 s over the Run tab's range, plus the current pace if it's between two.
        var options = unit == .metric
            ? Array(stride(from: 180.0, through: 600.0, by: 5.0))
            : Array(stride(from: 290.0, through: 965.0, by: 5.0))
        let current = perUnit.wrappedValue
        if current > 0, !options.contains(current) {
            options.append(current)
            options.sort()
        }
        return Picker("Target pace", selection: perUnit) {
            Text("Off").tag(0.0)
            ForEach(options, id: \.self) { pace in
                Text("\(RunFormat.pace(pace)) \(unit.paceSymbol)").tag(pace)
            }
        }
    }

    /// The runner's own pace for repeats this long, unless it's already the target.
    private var suggestedPace: (intensity: TrainingPaces.Intensity, perUnit: Double)? {
        guard let paces else { return nil }
        let intensity = TrainingPaces.Intensity.suited(to: work)
        let perUnit = TrainingPaces.perUnit(paces.pace(intensity), unit: unit).rounded()
        let current = workPace.map { TrainingPaces.perUnit($0, unit: unit).rounded() }
        return current == perUnit ? nil : (intensity, perUnit)
    }

    private var estimateFooter: String {
        if paces != nil { return "Estimated from your paces." }
        let easy = RunFormat.pace(TrainingPaces.perUnit(WorkoutEstimate.typicalEasyPace, unit: unit))
        let run = RunFormat.pace(TrainingPaces.perUnit(WorkoutEstimate.typicalRunPace, unit: unit))
        return "Estimated at \(easy) \(unit.paceSymbol) for the easy parts and \(run) \(unit.paceSymbol) for runs without a target."
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let workout else { return }
        name = workout.name
        guard let blueprint = workout.blueprint else {
            isEditable = false
            return
        }
        hasWarmup = blueprint.warmup != nil
        if let value = blueprint.warmup { warmup = value }
        repeats = blueprint.repeats
        work = blueprint.work
        workPace = blueprint.workPace
        if let value = blueprint.recovery { recovery = value }
        hasCooldown = blueprint.cooldown != nil
        if let value = blueprint.cooldown { cooldown = value }
    }

    private func save() {
        // Making and changing workouts is Stride Pro; this sheet only opens with it, but Pro can end meanwhile.
        guard ProStore.shared.isPro else {
            upsell = .workouts
            return
        }
        let blueprint = self.blueprint
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(CustomWorkout.maxNameLength))
        let finalName = trimmed.isEmpty ? blueprint.defaultName(unit: unit) : trimmed
        let target = workout ?? CustomWorkout(name: finalName, steps: blueprint.steps)
        target.name = finalName
        target.steps = blueprint.steps
        target.updatedAt = .now
        if workout == nil { context.insert(target) }
        try? context.save()
        // The Watch gets the new list right away.
        WatchSync.shared.pushSettings()
        onSave(target)
        dismiss()
    }

    /// The runner's own data: deleting never needs Pro.
    private func delete() {
        guard let workout else { return }
        dismiss()
        // Deleted once the sheet is gone, so neither it nor the list behind it renders a deleted model.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            context.delete(workout)
            try? context.save()
            WatchSync.shared.pushSettings()
        }
    }
}

/// Which common lengths a part of a workout offers.
enum WorkoutGoalRole {
    /// Warm-up and cool-down.
    case easy
    case work
    case recovery

    var times: [TimeInterval] {
        switch self {
        case .easy: ([3, 5, 8, 10, 12, 15, 20, 30] as [TimeInterval]).map { $0 * 60 }
        case .work: [15, 20, 30, 45, 60, 90, 120, 180, 240, 300, 360, 480, 600, 900, 1_200, 1_800, 2_700, 3_600]
        case .recovery: [15, 20, 30, 45, 60, 75, 90, 120, 150, 180, 240, 300]
        }
    }

    /// Meters. Short distances are track distances in both units; longer ones follow the unit.
    func distances(_ unit: UnitSystem) -> [Double] {
        let mile = UnitSystem.imperial.metersPerUnit
        let miles: ([Double]) -> [Double] = { values in values.map { $0 * mile } }
        switch (self, unit) {
        case (.easy, .metric): return [500, 1_000, 1_500, 2_000, 3_000, 5_000]
        case (.easy, .imperial): return miles([0.25, 0.5, 1, 1.5, 2, 3])
        case (.work, .metric): return [100, 200, 300, 400, 600, 800, 1_000, 1_200, 1_500, 2_000, 3_000, 5_000, 10_000]
        case (.work, .imperial): return [100, 200, 300, 400, 600, 800, 1_200] + miles([1, 1.5, 2, 3, 5])
        case (.recovery, _): return [100, 200, 300, 400, 600, 800]
        }
    }
}

/// One part of a workout by time or distance, from common values in one menu.
struct GoalPicker: View {
    let title: String
    @Binding var goal: WorkoutStep.Goal
    let role: WorkoutGoalRole
    let unit: UnitSystem

    var body: some View {
        Picker(title, selection: $goal) {
            Section("Time") {
                ForEach(times, id: \.self) { seconds in
                    Text(WorkoutBlueprint.text(for: .time(seconds), unit: unit)).tag(WorkoutStep.Goal.time(seconds))
                }
            }
            Section("Distance") {
                ForEach(distances, id: \.self) { meters in
                    Text(WorkoutBlueprint.text(for: .distance(meters), unit: unit)).tag(WorkoutStep.Goal.distance(meters))
                }
            }
        }
    }

    /// The role's lengths, plus the current one if it isn't among them (a workout from another unit).
    private var times: [TimeInterval] {
        var values = role.times
        if case .time(let current) = goal, !values.contains(current) {
            values.append(current)
            values.sort()
        }
        return values
    }

    private var distances: [Double] {
        var values = role.distances(unit)
        if case .distance(let current) = goal, !values.contains(current) {
            values.append(current)
            values.sort()
        }
        return values
    }
}

/// The workout at a glance, and roughly how long and how far it goes.
struct WorkoutSummaryRows: View {
    let steps: [WorkoutStep]
    let paces: TrainingPaces?
    let unit: UnitSystem

    var body: some View {
        let estimate = paces.map { WorkoutEstimate(steps: steps, paces: $0) } ?? WorkoutEstimate(steps: steps)
        WorkoutShapeBar(steps: steps, durations: estimate.stepDurations)
            .padding(.vertical, Space.x2)
        LabeledContent("Time", value: WorkoutLength.duration(estimate.duration, exact: estimate.isDurationExact))
        LabeledContent("Distance", value: WorkoutLength.distance(estimate.distance, exact: estimate.isDistanceExact, unit: unit))
    }
}

/// A workout's total time and distance in words, marked as an estimate unless every step is measured that way.
enum WorkoutLength {
    static func duration(_ seconds: TimeInterval, exact: Bool) -> String {
        guard !exact else { return RunFormat.duration(seconds) }
        let minutes = Int((max(seconds, 0) / 60).rounded())
        return minutes >= 60 ? "About \(minutes / 60) h \(minutes % 60) min" : "About \(minutes) min"
    }

    static func distance(_ meters: Double, exact: Bool, unit: UnitSystem) -> String {
        let value = RunFormat.distance(meters, unit: unit, fractionDigits: exact ? 2 : 1)
        return exact ? "\(value) \(unit.distanceSymbol)" : "About \(value) \(unit.distanceSymbol)"
    }
}

/// A workout at a glance: one bar per step, as wide as its (estimated) time, colored like the live
/// step card: runs in the brand color, recoveries in blue, warm-up and cool-down gray.
struct WorkoutShapeBar: View {
    let steps: [WorkoutStep]
    let durations: [TimeInterval]
    var height: CGFloat = 10

    var body: some View {
        let total = max(durations.reduce(0, +), 1)
        let gap: CGFloat = steps.count > 24 ? 1 : 2
        GeometryReader { geo in
            let available = max(geo.size.width - gap * CGFloat(max(steps.count - 1, 0)), 0)
            HStack(spacing: gap) {
                ForEach(steps.indices, id: \.self) { index in
                    let duration = durations.indices.contains(index) ? durations[index] : 0
                    RoundedRectangle(cornerRadius: min(height / 2, 3))
                        .fill(color(steps[index].kind))
                        .frame(width: max(available * duration / total, 2))
                }
            }
            .frame(width: geo.size.width, alignment: .leading)
            .clipped()
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }

    private func color(_ kind: WorkoutStep.Kind) -> Color {
        switch kind {
        case .run: .track
        case .recover: .lane
        case .warmup, .cooldown: .lineStrong
        }
    }
}
