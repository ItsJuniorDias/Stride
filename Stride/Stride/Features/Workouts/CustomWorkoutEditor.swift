import Foundation
import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// What the builder sheet opens on: a new workout, one to edit, or a new one starting from a preset.
enum WorkoutEditorTarget: Identifiable {
    case new
    case edit(CustomWorkout)
    /// A new workout shaped like a preset, to change and save as the runner's own.
    case preset(Workout)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let workout): workout.id.uuidString
        case .preset(let preset): "preset-\(preset.id)"
        }
    }

    var workout: CustomWorkout? {
        switch self {
        case .new, .preset: nil
        case .edit(let workout): workout
        }
    }

    /// Where a new workout starts, when not from the builder's own starter.
    var template: WorkoutBlueprint? {
        switch self {
        case .new, .edit: nil
        case .preset(let preset): WorkoutBlueprint(steps: preset.steps)
        }
    }
}

/// Builds or edits a custom workout (Stride Pro): a warm-up, repeats of a run with recoveries between
/// them, a cool-down, and the whole thing at a glance. Saved workouts are on the Run tab under
/// Intervals and on Apple Watch.
struct CustomWorkoutEditor: View {
    /// Nil for a new workout.
    let workout: CustomWorkout?
    /// A new workout's starting shape, e.g. a preset's; nil for the builder's starter.
    var template: WorkoutBlueprint? = nil
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
    /// The runner's paces, for the target pace choices and the estimate.
    @State private var paces: TrainingPaces?
    @State private var loaded = false
    /// False for steps a newer builder made: they run, but can't be changed here.
    @State private var isEditable = true
    @State private var confirmingDelete = false
    @State private var upsell: ProFeature?
    @FocusState private var nameFocused: Bool

    private var blueprint: WorkoutBlueprint {
        WorkoutBlueprint(warmup: hasWarmup ? warmup : nil, repeats: repeats, work: work, workPace: workPace,
                         recovery: recovery, cooldown: hasCooldown ? cooldown : nil)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x3) {
                    if isEditable {
                        nameCard
                        endCard(.warmup, isOn: $hasWarmup, goal: $warmup)
                        repeatCard
                        endCard(.cooldown, isOn: $hasCooldown, goal: $cooldown)
                    } else {
                        Text("This workout was made with a newer version of Stride. It runs as it is, but can't be changed here.")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .raisedCard()
                    }
                    if workout != nil {
                        Button("Delete workout", role: .destructive) { confirmingDelete = true }
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.danger)
                            .frame(maxWidth: .infinity, minHeight: Dimension.hitMin)
                            .padding(.top, Space.x2)
                    }
                }
                .padding(.horizontal, Space.x4)
                .padding(.top, Space.x3)
                .padding(.bottom, Space.x5)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.surface)
            .safeAreaInset(edge: .bottom) {
                if isEditable { summaryPanel }
            }
            .navigationTitle(workout == nil ? "New workout" : "Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear(perform: load)
            // After the sheet is up: reading every run's best efforts can take a moment.
            .task { paces = ProStore.shared.isPro ? PersonalPaces.current(in: context) : nil }
            .proPaywall($upsell)
            .confirmationDialog("Delete \(workout?.displayName ?? "workout")?", isPresented: $confirmingDelete,
                                titleVisibility: .visible) {
                Button("Delete workout", role: .destructive, action: delete)
            } message: {
                Text("Runs you did with it stay in your history.")
            }
        }
    }

    // MARK: Name and shape

    private var nameCard: some View {
        let steps = blueprint.steps
        return VStack(alignment: .leading, spacing: Space.x4) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Name").metricLabelStyle()
                HStack(spacing: Space.x2) {
                    TextField("Name", text: $name,
                              prompt: Text(blueprint.defaultName(unit: unit)).foregroundStyle(Color.inkMuted))
                        .font(.body)
                        .foregroundStyle(.ink)
                        .focused($nameFocused)
                        .submitLabel(.done)
                        .onChange(of: name) { _, value in
                            if value.count > CustomWorkout.maxNameLength { name = String(value.prefix(CustomWorkout.maxNameLength)) }
                        }
                    Image(systemName: "pencil")
                        .font(.body.weight(.medium))
                        .foregroundStyle(.inkMuted)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Space.x3)
                .frame(height: 48)
                .background(Color.surfaceSunken, in: RoundedRectangle(cornerRadius: Radius.md))
                .contentShape(RoundedRectangle(cornerRadius: Radius.md))
                .onTapGesture { nameFocused = true }
            }
            VStack(alignment: .leading, spacing: Space.x2) {
                StepStrip(steps: steps, paces: paces, style: .shaped, height: 32,
                          accessibilityLabel: StepStrip.summary(of: steps, unit: unit))
                    .animation(.snappy, value: steps)
                StepLegend()
            }
        }
        .raisedCard()
    }

    // MARK: Warm-up and cool-down

    private func endCard(_ kind: WorkoutStep.Kind, isOn: Binding<Bool>, goal: Binding<WorkoutStep.Goal>) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(kind.color)
                    .frame(width: 10, height: 10)
                    .accessibilityHidden(true)
                Toggle(kind.title, isOn: isOn.animation(.snappy))
                    .font(.headline)
                    .foregroundStyle(.ink)
                    .tint(.track)
            }
            .frame(minHeight: 32)
            if isOn.wrappedValue {
                WorkoutGoalControls(title: kind.title, goal: goal, role: .easy, unit: unit, pickerBackground: .surfaceSunken)
            }
        }
        .raisedCard()
    }

    // MARK: Repeats

    private var repeatCard: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x3) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Repeat").font(.headline).foregroundStyle(.ink)
                    Text("Run, then recover").font(.footnote).foregroundStyle(.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                WorkoutLengthStepper(label: "Repeats", value: "\(repeats)×", spokenValue: "\(repeats)",
                            valueFont: .metricSmall, valueMinWidth: 44,
                            canDecrease: repeats > WorkoutBlueprint.repeatRange.lowerBound,
                            canIncrease: repeats < WorkoutBlueprint.repeatRange.upperBound,
                            decreaseLabel: "Fewer repeats", increaseLabel: "More repeats") {
                    withAnimation(.snappy) { repeats -= 1 }
                } increase: {
                    withAnimation(.snappy) { repeats += 1 }
                }
            }

            StepBlock(kind: .run) {
                Text("Run").font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                WorkoutGoalControls(title: "Run", goal: $work, role: .work, unit: unit, pickerBackground: .surfaceRaised)
                targetPace
                    .padding(.top, 2)
            }

            if repeats > 1 {
                StepBlock(kind: .recover) {
                    Text("Recover").font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                    WorkoutGoalControls(title: "Recovery", goal: $recovery, role: .recovery, unit: unit, pickerBackground: .surfaceRaised)
                    Text("Skipped after the last run.").font(.footnote).foregroundStyle(.inkMuted)
                }
                .transition(.opacity)
            }
        }
        .raisedCard()
    }

    // MARK: Target pace

    /// The runner's easy, tempo or interval pace, their own, or none.
    private var targetPace: some View {
        let choice = currentChoice
        return VStack(alignment: .leading, spacing: Space.x2) {
            Text("Target pace").metricLabelStyle()
            ViewThatFits(in: .horizontal) {
                paceChips(choice)
                ScrollView(.horizontal, showsIndicators: false) { paceChips(choice) }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                Text(paceNote(choice))
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                customPaceMenu
            }
        }
    }

    private func paceChips(_ choice: PaceChoice?) -> some View {
        HStack(spacing: Space.x2) {
            ForEach(PaceChoice.allCases) { option in
                let isAvailable = option == .off || paces != nil
                PaceChip(title: option.title, isSelected: choice == option) { select(option) }
                    .disabled(!isAvailable)
                    .opacity(isAvailable ? 1 : 0.4)
            }
        }
    }

    /// Any pace, every 5 s over the Run tab's range: for a target that isn't one of the runner's paces.
    private var customPaceMenu: some View {
        let perUnit = Binding<Double>(
            get: { workPace.map { TrainingPaces.perUnit($0, unit: unit).rounded() } ?? 0 },
            set: { workPace = $0 > 0 ? $0 * 1_000 / unit.metersPerUnit : nil }
        )
        var options = unit == .metric
            ? Array(stride(from: 180.0, through: 600.0, by: 5.0))
            : Array(stride(from: 290.0, through: 965.0, by: 5.0))
        let current = perUnit.wrappedValue
        if current > 0, !options.contains(current) {
            options.append(current)
            options.sort()
        }
        return Menu {
            Picker("Target pace", selection: perUnit) {
                Text("Off").tag(0.0)
                ForEach(options, id: \.self) { pace in
                    Text("\(RunFormat.pace(pace)) \(unit.paceSymbol)").tag(pace)
                }
            }
        } label: {
            Text("Set a pace")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.lane)
                .frame(minHeight: Dimension.hitMin)
                .contentShape(Rectangle())
        }
        .padding(.vertical, -12)
        .fixedSize()
        .accessibilityLabel("Set your own target pace")
    }

    /// The chip the current target matches, or nil for a pace of the runner's own choosing.
    private var currentChoice: PaceChoice? {
        guard let workPace else { return .off }
        guard let paces else { return nil }
        let current = TrainingPaces.perUnit(workPace, unit: unit).rounded()
        return PaceChoice.allCases.first { option in
            option.intensity.map { TrainingPaces.perUnit(paces.pace($0), unit: unit).rounded() == current } ?? false
        }
    }

    /// Stored per kilometer, like every step target, from the pace as shown in the runner's unit.
    private func select(_ choice: PaceChoice) {
        guard let intensity = choice.intensity else {
            workPace = nil
            return
        }
        guard let paces else { return }
        workPace = TrainingPaces.perUnit(paces.pace(intensity), unit: unit).rounded() * 1_000 / unit.metersPerUnit
    }

    private func paceNote(_ choice: PaceChoice?) -> String {
        let coach = "The coach speaks up if you drift 10 s off."
        switch choice {
        case .off?:
            return paces == nil
                ? "No target. Run it by feel. Your own paces show up here after a few runs."
                : "No target. Run it by feel."
        case .easy?:
            return paces.map { "\($0.formatted(.easy, unit: unit)), your easy range." } ?? ""
        case .tempo?, .interval?:
            guard let workPace else { return "" }
            return "\(RunFormat.pace(TrainingPaces.perUnit(workPace, unit: unit))) \(unit.paceSymbol). \(coach)"
        case nil:
            guard let workPace else { return "" }
            return "\(RunFormat.pace(TrainingPaces.perUnit(workPace, unit: unit))) \(unit.paceSymbol), your own pace. \(coach)"
        }
    }

    // MARK: Summary

    /// Roughly how long and far, how many steps, and saving, floating over the builder.
    private var summaryPanel: some View {
        let steps = blueprint.steps
        let estimate = paces.map { WorkoutEstimate(steps: steps, paces: $0) } ?? WorkoutEstimate(steps: steps)
        let minutes = Int((estimate.duration / 60).rounded())
        return VStack(spacing: Space.x3) {
            HStack(alignment: .top, spacing: Space.x2) {
                StatTile(estimate.isDurationExact ? "Time" : "About", value: "\(minutes)", unit: "min")
                StatTile("Distance", value: RunFormat.distance(estimate.distance, unit: unit, fractionDigits: 1),
                         unit: unit.distanceSymbol)
                StatTile("Steps", value: "\(steps.count)")
            }
            Button("Save workout", action: save)
                .buttonStyle(.stridePrimary)
        }
        .padding(Space.x4)
        .floatingGlass(in: RoundedRectangle(cornerRadius: Radius.lg), interactive: false)
        .padding(.horizontal, Space.x4)
        .padding(.bottom, Space.x2)
        .accessibilityElement(children: .contain)
        .accessibilityHint(estimateHint)
    }

    private var estimateHint: String {
        if paces != nil { return "Estimated from your paces." }
        let easy = RunFormat.pace(TrainingPaces.perUnit(WorkoutEstimate.typicalEasyPace, unit: unit))
        let run = RunFormat.pace(TrainingPaces.perUnit(WorkoutEstimate.typicalRunPace, unit: unit))
        return "Estimated at \(easy) \(unit.paceSymbol) for the easy parts and \(run) \(unit.paceSymbol) for runs without a target."
    }

    // MARK: Load, save, delete

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let workout else {
            if let template { apply(template) }
            return
        }
        name = workout.name
        guard let blueprint = workout.blueprint else {
            isEditable = false
            return
        }
        apply(blueprint)
    }

    private func apply(_ blueprint: WorkoutBlueprint) {
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

/// The target pace chips: none, or one of the runner's own paces.
private enum PaceChoice: CaseIterable, Identifiable {
    case off, easy, tempo, interval

    var id: Self { self }

    var title: String {
        switch self {
        case .off: "Off"
        case .easy: "Easy"
        case .tempo: "Tempo"
        case .interval: "Interval"
        }
    }

    var intensity: TrainingPaces.Intensity? {
        switch self {
        case .off: nil
        case .easy: .easy
        case .tempo: .threshold
        case .interval: .interval
        }
    }
}

/// A single-select capsule like ``SelectableChip``, a little narrower so four fit across the builder.
private struct PaceChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .foregroundStyle(isSelected ? Color.onTrack : Color.ink)
                .background {
                    if isSelected {
                        Capsule().fill(Color.track)
                    } else {
                        Capsule().strokeBorder(Color.lineStrong, lineWidth: 1.5)
                    }
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -4)
        .fixedSize()
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// A part of the repeat block on a sunken well, with a stripe in the step's color down its edge.
private struct StepBlock<Content: View>: View {
    let kind: WorkoutStep.Kind
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .padding(Space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            ZStack(alignment: .leading) {
                Color.surfaceSunken
                Rectangle().fill(kind.color).frame(width: 3)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        }
    }
}

/// Which lengths a part of a workout steps through.
private enum WorkoutGoalRole {
    /// Warm-up and cool-down.
    case easy
    case work
    case recovery

    /// Seconds, shortest first: a minute at a time for warm-ups, 30 s for runs, 15 s for recoveries.
    var times: [TimeInterval] {
        switch self {
        case .easy:
            (1...30).map { TimeInterval($0) * 60 } + ([35, 40, 45, 50, 55, 60] as [TimeInterval]).map { $0 * 60 }
        case .work:
            ([15, 20, 30, 45] as [TimeInterval]) + Array(stride(from: 60.0, through: 1_200, by: 30))
                + ([1_500, 1_800, 2_100, 2_400, 2_700, 3_000, 3_600] as [TimeInterval])
        case .recovery:
            Array(stride(from: 15.0, through: 600, by: 15))
        }
    }

    /// Meters, shortest first. Short distances are track distances in both units; longer ones follow the unit.
    func distances(_ unit: UnitSystem) -> [Double] {
        let mile = UnitSystem.imperial.metersPerUnit
        let miles: ([Double]) -> [Double] = { values in values.map { $0 * mile } }
        switch (self, unit) {
        case (.easy, .metric): return Array(stride(from: 500.0, through: 5_000, by: 500))
        case (.easy, .imperial): return miles(Array(stride(from: 0.25, through: 3, by: 0.25)))
        case (.work, .metric):
            return Array(stride(from: 100.0, through: 2_000, by: 100)) + ([2_500, 3_000, 4_000, 5_000, 6_000, 8_000, 10_000] as [Double])
        case (.work, .imperial):
            return Array(stride(from: 100.0, through: 1_500, by: 100)) + miles([1, 1.25, 1.5, 2, 2.5, 3, 4, 5, 6])
        case (.recovery, _): return Array(stride(from: 100.0, through: 1_000, by: 100))
        }
    }

    /// The pace a length is converted at when switching between time and distance, seconds per km.
    var conversionPace: Double {
        self == .work ? WorkoutEstimate.typicalRunPace : WorkoutEstimate.typicalEasyPace
    }
}

/// By time or by distance.
private enum WorkoutGoalMode: CaseIterable {
    case time, distance

    var title: String { self == .time ? "Time" : "Distance" }
}

/// One part of a workout: time or distance, and a stepper through the role's lengths.
private struct WorkoutGoalControls: View {
    /// "Warm-up", "Run", "Recovery", for VoiceOver.
    let title: String
    @Binding var goal: WorkoutStep.Goal
    let role: WorkoutGoalRole
    let unit: UnitSystem
    /// `surfaceSunken` on a raised card, `surfaceRaised` on a sunken well.
    var pickerBackground: Color = .surfaceSunken

    var body: some View {
        let ladder = values
        let index = ladder.firstIndex(of: currentValue) ?? 0
        HStack(spacing: Space.x2) {
            PillPicker("\(title) by", selection: mode, options: role == .work ? [WorkoutGoalMode.distance, .time] : [WorkoutGoalMode.time, .distance],
                       background: pickerBackground) { $0.title }
            WorkoutLengthStepper(label: "\(title) length", value: WorkoutBlueprint.text(for: goal, unit: unit),
                        canDecrease: index > 0, canIncrease: index < ladder.count - 1,
                        decreaseLabel: "Shorter", increaseLabel: "Longer") {
                if index > 0 { set(ladder[index - 1]) }
            } increase: {
                if index < ladder.count - 1 { set(ladder[index + 1]) }
            }
        }
    }

    private var isTime: Bool {
        if case .time = goal { return true }
        return false
    }

    private var currentValue: Double {
        switch goal {
        case .time(let seconds): seconds
        case .distance(let meters): meters
        }
    }

    /// The role's lengths in the current mode, plus the current one if it isn't among them (a workout
    /// from another unit, or an older builder).
    private var values: [Double] {
        var ladder = isTime ? role.times : role.distances(unit)
        if !ladder.contains(currentValue) {
            ladder.append(currentValue)
            ladder.sort()
        }
        return ladder
    }

    private func set(_ value: Double) {
        withAnimation(.snappy) {
            goal = isTime ? .time(value) : .distance(value)
        }
    }

    /// Switching mode keeps about the same effort: 10 min easy becomes 1.5 km.
    private var mode: Binding<WorkoutGoalMode> {
        Binding {
            isTime ? .time : .distance
        } set: { newMode in
            switch (goal, newMode) {
            case (.time(let seconds), .distance):
                let meters = seconds / role.conversionPace * 1_000
                goal = .distance(Self.nearest(meters, in: role.distances(unit)))
            case (.distance(let meters), .time):
                let seconds = meters / 1_000 * role.conversionPace
                goal = .time(Self.nearest(seconds, in: role.times))
            default:
                break
            }
        }
    }

    private static func nearest(_ value: Double, in ladder: [Double]) -> Double {
        ladder.min { abs($0 - value) < abs($1 - value) } ?? value
    }
}

/// − value +, on an outlined capsule. VoiceOver reads it as one adjustable control.
private struct WorkoutLengthStepper: View {
    let label: String
    let value: String
    /// What VoiceOver reads for the value, when the shown one has a symbol in it ("6×").
    var spokenValue: String? = nil
    var valueFont: Font = .headline
    var valueMinWidth: CGFloat = 64
    let canDecrease: Bool
    let canIncrease: Bool
    let decreaseLabel: String
    let increaseLabel: String
    let decrease: () -> Void
    let increase: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            button("minus", label: decreaseLabel, enabled: canDecrease, action: decrease)
            Text(value)
                .font(valueFont)
                .monospacedDigit()
                .foregroundStyle(.ink)
                .lineLimit(1)
                .contentTransition(.numericText())
                .frame(minWidth: valueMinWidth)
            button("plus", label: increaseLabel, enabled: canIncrease, action: increase)
        }
        .frame(height: Dimension.hitMin)
        .overlay { Capsule().strokeBorder(Color.lineStrong, lineWidth: 1.5) }
        .fixedSize()
        .sensoryFeedback(.selection, trigger: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue ?? value)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: if canIncrease { increase() }
            case .decrement: if canDecrease { decrease() }
            @unknown default: break
            }
        }
    }

    private func button(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? Color.ink : Color.lineStrong)
        .disabled(!enabled)
        .accessibilityLabel(label)
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

    /// "45 min", "1 h 5 min": for lists, where the numbers are read as rough anyway.
    static func minutes(_ seconds: TimeInterval) -> String {
        let minutes = Int((max(seconds, 0) / 60).rounded())
        return minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
    }
}
