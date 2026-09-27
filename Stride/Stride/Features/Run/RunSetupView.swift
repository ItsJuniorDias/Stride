import SwiftUI
import SwiftData
import MapKit
import StrideKit
import StrideUI

/// Pick a run type and target, check GPS, and start.
struct RunSetupView: View {
    @Environment(RunTracker.self) private var tracker
    @Environment(MirroredWorkout.self) private var mirrored
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<Shoe> { !$0.isRetired }, sort: \Shoe.createdAt) private var shoes: [Shoe]
    /// The runner's own interval workouts, after the presets.
    @Query(sort: \CustomWorkout.createdAt) private var customWorkouts: [CustomWorkout]
    /// Newest first: best times, predictions and the usual pace behind the target captions.
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.autoPause) private var autoPause = true
    /// Seconds per kilometer, 0 when off. Remembered between runs.
    @AppStorage(StrideSettings.targetPace) private var targetPace = 0.0
    /// The interval workout picked: a preset's id or a custom workout's ``CustomWorkout/workoutID``.
    @State private var intervalWorkoutID = IntervalPresets.all[0].id
    @State private var editingWorkout: WorkoutEditorTarget?

    @State private var runType: RunType = .free
    @State private var targetMeters: Double = 5_000
    @State private var targetMinutes = 30
    /// The default shoe: picking one here makes it the shoe for Apple Watch and manual runs too.
    @AppStorage(StrideSettings.defaultShoeID) private var defaultShoeRaw = ""
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var upsell: ProFeature?
    /// Worked out from the runs when they change, not on every redraw.
    @State private var stats = SetupStats()

    /// Intervals and target-pace alerts come with Stride Pro.
    private var isPro: Bool { ProStore.shared.isPro }

    private let runTypes: [RunType] = [.free, .distance, .time, .intervals]

    /// The default shoe while it's still active.
    private var shoeID: UUID? {
        UUID(uuidString: defaultShoeRaw).flatMap { id in shoes.contains { $0.id == id } ? id : nil }
    }

    private var shoeSelection: Binding<UUID?> {
        Binding(get: { shoeID }, set: { defaultShoeRaw = $0?.uuidString ?? "" })
    }

    /// The workout picked under Intervals: a preset, or one of the runner's own. The first preset when
    /// the picked one was deleted (here, in Profile or on another device).
    private var intervalWorkout: Workout {
        if let preset = IntervalPresets.all.first(where: { $0.id == intervalWorkoutID }) { return preset }
        if let custom = customWorkouts.first(where: { $0.workoutID == intervalWorkoutID && $0.isRunnable }) {
            return custom.workout(unit: unit)
        }
        return IntervalPresets.all[0]
    }

    /// Target paces offered, every 5 s, in seconds per the runner's unit:
    /// 3'00"–10'00" per km, 4'50"–16'05" per mile (the same range).
    private var paceOptions: [Double] {
        unit == .metric ? Array(stride(from: 180.0, through: 600.0, by: 5.0)) : Array(stride(from: 290.0, through: 965.0, by: 5.0))
    }
    private let timeOptions = [15, 20, 30, 45, 60, 90]

    private struct DistancePreset: Hashable {
        let label: String
        let meters: Double
        /// The best effort Stride keeps for this distance, if it keeps one.
        var effort: EffortDistance? = nil
        /// How a caption names it: "3 km", "half marathon".
        var name: String? = nil
    }

    /// Race distances are exact in both unit systems; everyday distances follow the runner's unit.
    private var distancePresets: [DistancePreset] {
        let half = DistancePreset(label: "Half", meters: 21_097.5, effort: .half, name: "half marathon")
        let marathon = DistancePreset(label: "Marathon", meters: 42_195, effort: .marathon, name: "marathon")
        switch unit {
        case .metric:
            return [DistancePreset(label: "1 km", meters: 1_000, effort: .oneK),
                    DistancePreset(label: "3 km", meters: 3_000),
                    DistancePreset(label: "5 km", meters: 5_000, effort: .fiveK),
                    DistancePreset(label: "10 km", meters: 10_000, effort: .tenK),
                    half, marathon]
        case .imperial:
            let miles = { (n: Int) in DistancePreset(label: "\(n) mi", meters: Double(n) * 1_609.344) }
            return [DistancePreset(label: "1 mi", meters: 1_609.344, effort: .oneMile), miles(2),
                    DistancePreset(label: "5K", meters: 5_000, effort: .fiveK), miles(5),
                    DistancePreset(label: "10K", meters: 10_000, effort: .tenK), half, marathon]
        }
    }

    /// The chosen target if it's one of the current unit's presets, otherwise 5K, so the highlighted
    /// chip and the run's target always agree after a unit change.
    private var selectedMeters: Double {
        distancePresets.contains { $0.meters == targetMeters } ? targetMeters : 5_000
    }

    private var canStart: Bool { !tracker.authorizationDenied && !tracker.accuracyLimited }

    /// Changes when the captions may have: a run added, removed or re-analyzed.
    private var statsKey: String {
        "\(runs.count)-\(runs.first?.startDate.timeIntervalSince1970 ?? 0)-\(runs.reduce(0) { $0 + $1.effortsVersion })"
    }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .overlay(alignment: .topTrailing) {
            GlassIconButton("location.fill", accessibilityLabel: "Center on your location", tint: .lane) {
                withAnimation { camera = .userLocation(fallback: .automatic) }
            }
            .padding(.trailing, Space.x4)
            .padding(.top, Space.x2)
        }
        // An inset, not an overlay, so the map centers the runner in the area above the panel.
        .safeAreaInset(edge: .bottom) {
            panel
                .padding(.horizontal, Space.x4)
                .padding(.bottom, Space.x3)
        }
        .onAppear { tracker.startPreview() }
        .onDisappear { tracker.stopPreview() }
        .task(id: statsKey) { stats = SetupStats(runs) }
        .alert("Apple Watch", isPresented: Binding(get: { mirrored.error != nil }, set: { if !$0 { mirrored.clearError() } })) {
            Button("OK") {}
        } message: {
            Text(mirrored.error ?? "")
        }
        .proPaywall($upsell)
        .sheet(item: $editingWorkout) { target in
            // A saved workout is the one picked, ready to start.
            CustomWorkoutEditor(workout: target.workout) { intervalWorkoutID = $0.workoutID }
        }
        // Pro ended while Intervals was picked: back to a free run.
        .onChange(of: isPro) { _, isPro in
            if !isPro, runType == .intervals { runType = .free }
        }
    }

    // MARK: Panel

    private var panel: some View {
        VStack(spacing: Space.x4) {
            HStack(spacing: Space.x2) {
                GPSChip(quality: tracker.gpsQuality)
                Spacer(minLength: 0)
                if mirrored.canStartOnWatch {
                    startOnWatchButton
                }
            }

            if tracker.authorizationDenied {
                locationBanner(title: "Location is off for Stride",
                               message: "Turn on location access to record your route, distance and pace.")
            } else if tracker.accuracyLimited {
                locationBanner(title: "Precise Location is off",
                               message: "Stride needs Precise Location to measure distance and pace. Turn it on in Settings.")
            }

            VStack(alignment: .leading, spacing: Space.x3) {
                runTypeRow
                targetPicker
            }

            settings

            RunControlButton(.start) { tracker.start(configuration) }
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.4)
        }
        .padding(Space.x4)
        .glassPanel()
    }

    private var startOnWatchButton: some View {
        Button {
            Task { await mirrored.startOnWatch(goal: watchGoal) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "applewatch")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text(mirrored.isStartingOnWatch ? "Opening…" : "Start on Watch")
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.ink)
            .padding(.leading, Space.x3)
            .padding(.trailing, 14)
            .frame(minHeight: 36)
            .background(Capsule().strokeBorder(Color.lineStrong, lineWidth: 1.5))
            .frame(minHeight: Dimension.hitMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -Space.x1)
        .disabled(mirrored.isStartingOnWatch)
        .accessibilityHint("Starts a run on your Apple Watch and shows it live here.")
    }

    /// Free, Distance, Time, Intervals, sharing the width; a scrolling row when they don't fit
    /// (large text, or the Pro tag on Intervals).
    private var runTypeRow: some View {
        ViewThatFits(in: .horizontal) {
            FillRow(spacing: Space.x2) {
                runTypeChips(fill: true)
            }
            chipRow {
                runTypeChips(fill: false)
            }
        }
        // The chips' 44pt tap areas overlap the rows around them, as drawn.
        .padding(.vertical, -Space.x1)
    }

    @ViewBuilder private func runTypeChips(fill: Bool) -> some View {
        ForEach(runTypes) { type in
            let locked = type == .intervals && !isPro
            RunTypeChip(title: type == .free ? "Free" : type.title, isSelected: runType == type,
                        tag: locked ? "Pro" : nil, fills: fill) {
                if locked { upsell = .intervals } else { runType = type }
            }
            .accessibilityHint(locked ? "Needs Stride Pro" : "")
        }
    }

    @ViewBuilder private var targetPicker: some View {
        switch runType {
        case .distance:
            VStack(alignment: .leading, spacing: Space.x2) {
                chipRow {
                    ForEach(distancePresets, id: \.self) { preset in
                        SelectableChip(preset.label, isSelected: selectedMeters == preset.meters) {
                            targetMeters = preset.meters
                        }
                    }
                }
                if let preset = distancePresets.first(where: { $0.meters == selectedMeters }),
                   let caption = caption(for: preset) {
                    captionText(caption)
                }
            }
        case .time:
            VStack(alignment: .leading, spacing: Space.x2) {
                chipRow {
                    ForEach(timeOptions, id: \.self) { minutes in
                        SelectableChip("\(minutes) min", isSelected: targetMinutes == minutes) {
                            targetMinutes = minutes
                        }
                    }
                }
                if let caption = timeCaption {
                    captionText(caption)
                }
            }
        case .intervals:
            intervalsPicker
        case .free:
            Text("Run at your own pace. Stride records everything.")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A row of chips that scrolls to the panel's edges.
    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.x2) {
                content()
            }
        }
        .contentMargins(.horizontal, Space.x4, for: .scrollContent)
        .padding(.horizontal, -Space.x4)
    }

    private func captionText(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .monospacedDigit()
            .foregroundStyle(.inkMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentTransition(.opacity)
    }

    /// The runner's best time at the distance, and the predicted time with Stride Pro:
    /// "Your best 24:12 · Predicted 23:58", "Your best 1K is 4:21", "Predicted 1:51:20".
    private func caption(for preset: DistancePreset) -> String? {
        let predicted = isPro ? preset.effort.flatMap { stats.predictions?[$0]?.time } : nil
        if let effort = preset.effort, let best = stats.best[effort] {
            if let predicted {
                return "Your best \(RunFormat.duration(best)) · Predicted \(RunFormat.duration(predicted))"
            }
            return "Your best \(Self.bestName(effort)) is \(RunFormat.duration(best))"
        }
        if let predicted {
            return "Predicted \(RunFormat.duration(predicted))"
        }
        // Stride keeps no record at this distance: an estimate from the runner's usual pace instead.
        if preset.effort == nil, let pace = stats.usualPace {
            return "At your usual pace, about \(RunFormat.duration(pace * preset.meters))"
        }
        return "No record at \(preset.name ?? preset.label) yet"
    }

    private static func bestName(_ effort: EffortDistance) -> String {
        effort == .oneMile ? "mile" : effort.title
    }

    /// "At your usual pace, about 5.2 km".
    private var timeCaption: String? {
        guard let pace = stats.usualPace, pace > 0 else { return nil }
        let meters = Double(targetMinutes * 60) / pace
        return "At your usual pace, about \(RunFormat.distance(meters, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
    }

    /// The presets, then the runner's own workouts after a way to build one (Stride Pro), then the
    /// picked workout at a glance.
    private var intervalsPicker: some View {
        let selected = intervalWorkout
        let own = customWorkouts.filter(\.isRunnable)
        let selectedOwn = own.first { $0.workoutID == selected.id }
        return VStack(alignment: .leading, spacing: Space.x3) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Presets").metricLabelStyle()
                chipRow {
                    ForEach(IntervalPresets.all) { preset in
                        SelectableChip(preset.name, isSelected: selected.id == preset.id) {
                            intervalWorkoutID = preset.id
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Your workouts").metricLabelStyle()
                chipRow {
                    BuildWorkoutChip(isLocked: !isPro) {
                        if isPro { editingWorkout = .new } else { upsell = .workouts }
                    }
                    ForEach(own) { custom in
                        SelectableChip(custom.displayName, isSelected: selected.id == custom.workoutID) {
                            intervalWorkoutID = custom.workoutID
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { edit(custom) }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: Space.x2) {
                HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                    Text(selected.detail)
                        .font(.subheadline)
                        .foregroundStyle(.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let selectedOwn {
                        Button("Edit") { edit(selectedOwn) }
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.lane)
                            .accessibilityLabel("Edit \(selectedOwn.displayName)")
                    }
                }
                StepStrip(steps: selected.steps, paces: stats.paces, height: 8,
                          accessibilityLabel: StepStrip.summary(of: selected.steps, unit: unit))
                HStack(spacing: Space.x2) {
                    StepLegend(warmUpTitle: "Warm-up", font: .caption2.weight(.semibold), spacing: Space.x3)
                    Spacer(minLength: 0)
                    Text(aboutText(selected))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.inkMuted)
                        .lineLimit(1)
                }
            }
            .padding(.top, 2)
        }
    }

    /// "About 45 min", from the runner's paces when there are enough runs, typical ones otherwise.
    private func aboutText(_ workout: Workout) -> String {
        let estimate = stats.paces.map { WorkoutEstimate(steps: workout.steps, paces: $0) }
            ?? WorkoutEstimate(steps: workout.steps)
        let minutes = Int((estimate.duration / 60).rounded())
        return minutes >= 60 ? "About \(minutes / 60) h \(minutes % 60) min" : "About \(minutes) min"
    }

    /// Changing a workout is Stride Pro, like building one.
    private func edit(_ workout: CustomWorkout) {
        if isPro { editingWorkout = .edit(workout) } else { upsell = .workouts }
    }

    // MARK: Settings

    /// Shoe, auto-pause and target pace side by side on a sunken strip.
    private var settings: some View {
        DividedGrid(columns: shoes.isEmpty ? 2 : 3, dividers: .all, cellPadding: EdgeInsets(),
                    fill: Color.surfaceSunken.opacity(0.85)) {
            if !shoes.isEmpty {
                shoeCell
            }
            autoPauseCell
            targetPaceCell
        }
    }

    private var shoeName: String {
        shoes.first { $0.id == shoeID }?.displayName ?? "None"
    }

    private var shoeCell: some View {
        Menu {
            Picker("Shoe", selection: shoeSelection) {
                Text("No shoe").tag(UUID?.none)
                ForEach(shoes) { shoe in
                    Text(shoe.displayName).tag(UUID?.some(shoe.id))
                }
            }
        } label: {
            SettingCell(label: "Shoe") {
                Text(shoeName)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.ink)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("Shoe, \(shoeName)")
    }

    private var autoPauseCell: some View {
        Button {
            autoPause.toggle()
        } label: {
            SettingCell(label: "Auto-pause") {
                MiniSwitch(isOn: autoPause)
            }
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: autoPause)
        .accessibilityRepresentation {
            Toggle("Auto-pause", isOn: $autoPause)
        }
    }

    /// Off, or a pace to hold; the coach says when the runner drifts more than 10 s off it. A Stride Pro
    /// feature: without Pro the cell opens the paywall, and a pace remembered from before is kept but unused.
    @ViewBuilder private var targetPaceCell: some View {
        if isPro {
            targetPaceMenu
        } else {
            Button { upsell = .targetPace } label: {
                SettingCell(label: "Target pace") {
                    TagBadge("Pro")
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Target pace")
            .accessibilityHint("Needs Stride Pro")
        }
    }

    private var targetPaceMenu: some View {
        let perUnit = Binding<Double>(
            // Rounded to a 5 s option and kept inside the list, so the picker always has a matching tag.
            get: {
                guard targetPace > 0, let first = paceOptions.first, let last = paceOptions.last else { return 0 }
                return min(max((targetPace * unit.metersPerUnit / 1_000 / 5).rounded() * 5, first), last)
            },
            set: { targetPace = $0 > 0 ? $0 * 1_000 / unit.metersPerUnit : 0 }
        )
        let value = targetPace > 0 ? "\(RunFormat.pace(perUnit.wrappedValue)) \(unit.paceSymbol)" : "Off"
        return Menu {
            Picker("Target pace", selection: perUnit) {
                Text("Off").tag(0.0)
                ForEach(paceOptions, id: \.self) { pace in
                    Text("\(RunFormat.pace(pace)) \(unit.paceSymbol)").tag(pace)
                }
            }
        } label: {
            SettingCell(label: "Target pace") {
                Text(value)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.ink)
                    .lineLimit(1)
            }
        }
        .accessibilityLabel("Target pace, \(value)")
    }

    private func locationBanner(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.lane)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.x4)
        .background(Color.trackSoft, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: Run

    /// The target picked here, for a run started with "Start on Watch".
    private var watchGoal: MirrorGoal? {
        switch runType {
        case .distance:
            let label = distancePresets.first { $0.meters == selectedMeters }?.label
            return MirrorGoal(type: .distance, distance: selectedMeters, name: label)
        case .time:
            return MirrorGoal(type: .time, duration: TimeInterval(targetMinutes * 60), name: "\(targetMinutes) min")
        case .intervals:
            // The workout an iPhone run would follow (none without Pro); the Watch runs its steps.
            guard let workout = configuration.workout else { return nil }
            return MirrorGoal(type: .intervals, name: workout.name, workout: workout)
        case .free:
            return nil
        }
    }

    private var configuration: RunTracker.Configuration {
        var configuration = RunTracker.Configuration(type: runType, shoeID: shoeID, autoPause: autoPause)
        configuration.targetPace = targetPace > 0 && isPro ? targetPace : nil
        switch runType {
        case .distance: configuration.targetDistance = selectedMeters
        case .time: configuration.targetDuration = TimeInterval(targetMinutes * 60)
        case .intervals: configuration.workout = isPro ? intervalWorkout : nil
        case .free: break
        }
        return configuration
    }
}

/// What the setup panel knows from past runs: best times, race predictions, training paces and the
/// usual pace.
private struct SetupStats {
    var best: [EffortDistance: TimeInterval] = [:]
    var predictions: RacePredictions?
    var paces: TrainingPaces?
    /// Seconds per meter over the last ten runs of 1 km or more.
    var usualPace: Double?

    init() {}

    /// `runs` newest first.
    init(_ runs: [Run]) {
        let entries = runs.map(\.recordEntry)
        for (kind, record) in PersonalRecords.best(of: entries) {
            if case .effort(let distance) = kind { best[distance] = record.value }
        }
        predictions = RacePredictor.predict(from: entries)
        paces = predictions?.trainingPaces
        let recent = runs.filter { $0.distance >= 1_000 && $0.duration > 0 }.prefix(10)
        let meters = recent.reduce(0) { $0 + $1.distance }
        let seconds = recent.reduce(0) { $0 + $1.duration }
        usualPace = meters > 0 ? seconds / meters : nil
    }
}

/// A run type in the panel's top row: 36pt capsule in a 44pt tap area, filling its share of the
/// width when `fills`. An optional tag (PRO) follows the title while it isn't selected.
private struct RunTypeChip: View {
    let title: String
    let isSelected: Bool
    let tag: String?
    let fills: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                    .lineLimit(1)
                if let tag, !isSelected { TagBadge(tag) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isSelected ? Color.onTrack : Color.ink)
            .padding(.horizontal, Space.x3)
            .frame(maxWidth: fills ? .infinity : nil, minHeight: 36)
            .background {
                if isSelected {
                    Capsule().fill(Color.track)
                } else {
                    Capsule().strokeBorder(Color.lineStrong, lineWidth: 1.5)
                }
            }
            .frame(minHeight: Dimension.hitMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// Children at their natural width, with the room left over shared equally between them (the run
/// types: "Distance" keeps its length, every chip grows by the same amount).
private nonisolated struct FillRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = naturalWidth(sizes)
        return CGSize(width: proposal.width.map { max($0, natural) } ?? natural,
                      height: sizes.map(\.height).max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let extra = sizes.isEmpty ? 0 : max(bounds.width - naturalWidth(sizes), 0) / CGFloat(sizes.count)
        var x = bounds.minX
        for (subview, size) in zip(subviews, sizes) {
            let width = size.width + extra
            subview.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func naturalWidth(_ sizes: [CGSize]) -> CGFloat {
        sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(sizes.count - 1, 0))
    }
}

/// A cell of the settings strip: an overline and its value, the whole cell tappable.
private struct SettingCell<Value: View>: View {
    let label: String
    @ViewBuilder let value: Value

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .metricLabelStyle()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            value
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// The small switch drawn in the settings strip; the cell around it is the control.
private struct MiniSwitch: View {
    let isOn: Bool

    var body: some View {
        Capsule()
            .fill(isOn ? Color.track : Color.line)
            .frame(width: 36, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                    .padding(2)
            }
            .animation(.snappy(duration: 0.2), value: isOn)
            .accessibilityHidden(true)
    }
}

/// The first chip under Your workouts: builds a workout of the runner's own. Dashed, as it adds
/// rather than picks.
private struct BuildWorkoutChip: View {
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .bold))
                    .accessibilityHidden(true)
                Text("Build your own")
                if isLocked { TagBadge("Pro") }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.ink)
            .padding(.leading, Space.x3)
            .padding(.trailing, Space.x4)
            .frame(minHeight: 36)
            .background(Capsule().strokeBorder(Color.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isLocked ? "Needs Stride Pro" : "Opens the workout builder")
    }
}
