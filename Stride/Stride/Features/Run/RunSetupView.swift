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
    }

    /// Race distances are exact in both unit systems; everyday distances follow the runner's unit.
    private var distancePresets: [DistancePreset] {
        let half = DistancePreset(label: "Half", meters: 21_097.5)
        let marathon = DistancePreset(label: "Marathon", meters: 42_195)
        switch unit {
        case .metric:
            return [1, 3, 5, 10].map { DistancePreset(label: "\($0) km", meters: Double($0) * 1_000) } + [half, marathon]
        case .imperial:
            let miles = { (n: Int) in DistancePreset(label: "\(n) mi", meters: Double(n) * 1_609.344) }
            return [miles(1), miles(2), DistancePreset(label: "5K", meters: 5_000), miles(5),
                    DistancePreset(label: "10K", meters: 10_000), half, marathon]
        }
    }

    /// The chosen target if it's one of the current unit's presets, otherwise 5K, so the highlighted
    /// chip and the run's target always agree after a unit change.
    private var selectedMeters: Double {
        distancePresets.contains { $0.meters == targetMeters } ? targetMeters : 5_000
    }

    private var canStart: Bool { !tracker.authorizationDenied && !tracker.accuracyLimited }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
        }
        // An inset, not an overlay, so the map centers the runner in the area above the panel.
        .safeAreaInset(edge: .bottom) {
            panel
                .padding(.horizontal, Space.x4)
                .padding(.bottom, Space.x2)
        }
        .onAppear { tracker.startPreview() }
        .onDisappear { tracker.stopPreview() }
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

    private var panel: some View {
        VStack(spacing: Space.x4) {
            HStack {
                GPSChip(quality: tracker.gpsQuality)
                Spacer()
                if mirrored.canStartOnWatch {
                    Button {
                        Task { await mirrored.startOnWatch(goal: watchGoal) }
                    } label: {
                        Label(mirrored.isStartingOnWatch ? "Opening…" : "Start on Watch", systemImage: "applewatch")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.ink)
                            .padding(.horizontal, Space.x3)
                            .frame(minHeight: 36)
                            .background(Capsule().strokeBorder(Color.lineStrong, lineWidth: 1.5))
                    }
                    .disabled(mirrored.isStartingOnWatch)
                    .accessibilityHint("Starts a run on your Apple Watch and shows it live here.")
                }
            }

            if tracker.authorizationDenied {
                locationBanner(title: "Location is off for Stride",
                               message: "Turn on location access to record your route, distance and pace.")
            } else if tracker.accuracyLimited {
                locationBanner(title: "Precise Location is off",
                               message: "Stride needs Precise Location to measure distance and pace. Turn it on in Settings.")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x2) {
                    ForEach(runTypes) { type in
                        let locked = type == .intervals && !isPro
                        SelectableChip(type.title, isSelected: runType == type, tag: locked ? "Pro" : nil) {
                            if locked { upsell = .intervals } else { runType = type }
                        }
                        .accessibilityHint(locked ? "Needs Stride Pro" : "")
                    }
                }
            }

            targetPicker
                .frame(minHeight: 36)

            settings

            RunControlButton(.start) { tracker.start(configuration) }
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.4)
        }
        .padding(Space.x4)
        .glassPanel()
    }

    @ViewBuilder private var targetPicker: some View {
        switch runType {
        case .distance:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x2) {
                    ForEach(distancePresets, id: \.self) { preset in
                        SelectableChip(preset.label, isSelected: selectedMeters == preset.meters) {
                            targetMeters = preset.meters
                        }
                    }
                }
            }
        case .time:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x2) {
                    ForEach(timeOptions, id: \.self) { minutes in
                        SelectableChip("\(minutes) min", isSelected: targetMinutes == minutes) {
                            targetMinutes = minutes
                        }
                    }
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

    /// The presets, then the runner's own workouts, then a way to build one (Stride Pro).
    private var intervalsPicker: some View {
        let selected = intervalWorkout
        let own = customWorkouts.filter(\.isRunnable)
        let selectedOwn = own.first { $0.workoutID == selected.id }
        return VStack(alignment: .leading, spacing: Space.x2) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x2) {
                    ForEach(IntervalPresets.all) { preset in
                        SelectableChip(preset.name, isSelected: selected.id == preset.id) {
                            intervalWorkoutID = preset.id
                        }
                    }
                    ForEach(own) { custom in
                        SelectableChip(custom.displayName, isSelected: selected.id == custom.workoutID) {
                            intervalWorkoutID = custom.workoutID
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { edit(custom) }
                        }
                    }
                    BuildWorkoutChip(isLocked: !isPro) {
                        if isPro { editingWorkout = .new } else { upsell = .workouts }
                    }
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                Text(selected.detail)
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if let selectedOwn {
                    Button("Edit") { edit(selectedOwn) }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.lane)
                        .accessibilityLabel("Edit \(selectedOwn.displayName)")
                }
            }
        }
    }

    /// Changing a workout is Stride Pro, like building one.
    private func edit(_ workout: CustomWorkout) {
        if isPro { editingWorkout = .edit(workout) } else { upsell = .workouts }
    }

    /// Shoe and auto-pause as settings rows, grouped like a small form.
    private var settings: some View {
        VStack(spacing: 0) {
            if !shoes.isEmpty {
                Menu {
                    Picker("Shoe", selection: shoeSelection) {
                        Text("No shoe").tag(UUID?.none)
                        ForEach(shoes) { shoe in
                            Text(shoe.name).tag(UUID?.some(shoe.id))
                        }
                    }
                } label: {
                    HStack(spacing: Space.x2) {
                        Label("Shoe", systemImage: "shoe.fill")
                            .foregroundStyle(.ink)
                        Spacer()
                        Text(shoes.first { $0.id == shoeID }?.name ?? "None")
                            .foregroundStyle(.inkMuted)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.inkMuted)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, Space.x4)
                    .frame(minHeight: Dimension.hitMin)
                    .contentShape(Rectangle())
                }
                Divider()
                    .overlay(Color.line)
                    .padding(.leading, Space.x4)
            }
            Toggle(isOn: $autoPause) {
                Label("Auto-pause", systemImage: "pause.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink)
            }
            .tint(.track)
            .padding(.horizontal, Space.x4)
            .frame(minHeight: Dimension.hitMin)
            Divider()
                .overlay(Color.line)
                .padding(.leading, Space.x4)
            targetPaceRow
        }
        .background(Color.surfaceSunken.opacity(0.85), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    /// Off, or a pace to hold; the coach says when the runner drifts more than 10 s off it. A Stride Pro
    /// feature: without Pro the row opens the paywall, and a pace remembered from before is kept but unused.
    @ViewBuilder private var targetPaceRow: some View {
        if isPro {
            targetPaceMenu
        } else {
            Button { upsell = .targetPace } label: {
                HStack(spacing: Space.x2) {
                    Label("Target pace", systemImage: "gauge.with.needle")
                        .foregroundStyle(.ink)
                    Spacer()
                    TagBadge("Pro")
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, Space.x4)
                .frame(minHeight: Dimension.hitMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
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
        return Menu {
            Picker("Target pace", selection: perUnit) {
                Text("Off").tag(0.0)
                ForEach(paceOptions, id: \.self) { pace in
                    Text("\(RunFormat.pace(pace)) \(unit.paceSymbol)").tag(pace)
                }
            }
        } label: {
            HStack(spacing: Space.x2) {
                Label("Target pace", systemImage: "gauge.with.needle")
                    .foregroundStyle(.ink)
                Spacer()
                Text(targetPace > 0 ? "\(RunFormat.pace(perUnit.wrappedValue)) \(unit.paceSymbol)" : "Off")
                    .foregroundStyle(.inkMuted)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, Space.x4)
            .frame(minHeight: Dimension.hitMin)
            .contentShape(Rectangle())
        }
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

/// The last chip under Intervals: builds a workout of the runner's own. Dashed, as it adds rather than picks.
private struct BuildWorkoutChip: View {
    let isLocked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.x2) {
                Image(systemName: "plus")
                    .font(.subheadline.weight(.bold))
                Text("Build your own")
                if isLocked { TagBadge("Pro") }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.ink)
            .padding(.horizontal, Space.x4)
            .frame(minHeight: 36)
            .background(Capsule().strokeBorder(Color.lineStrong, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(isLocked ? "Needs Stride Pro" : "Opens the workout builder")
    }
}
