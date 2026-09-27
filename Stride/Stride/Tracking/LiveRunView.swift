import SwiftUI
import SwiftData
import MapKit
import StrideKit
import StrideUI

/// The full-screen run: countdown, live metrics or map, controls, then the summary.
struct LiveRunView: View {
    @Environment(RunTracker.self) private var tracker
    @Environment(\.modelContext) private var context
    @State private var showingMap = false
    @State private var isLocked = false
    @State private var confirmingDiscard = false
    /// The last visible state, kept while the cover animates away after the tracker resets.
    @State private var lastPhase: RunTracker.Phase = .countdown(3)
    @State private var lastRun: Run?
    @State private var lastAchievements: [RecordAchievement] = []

    private var displayedPhase: RunTracker.Phase {
        tracker.phase == .idle ? lastPhase : tracker.phase
    }

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()
            switch displayedPhase {
            case .countdown(let number):
                CountdownView(number: number, gpsQuality: tracker.gpsQuality, goal: countdownGoal,
                              message: countdownMessage,
                              onSkip: { tracker.startNow() }, onCancel: { tracker.cancelCountdown() })
            case .finished:
                if let run = tracker.finishedRun ?? lastRun {
                    RunSummaryView(run: run, achievements: tracker.phase == .idle ? lastAchievements : tracker.finishedAchievements)
                }
            case .running, .paused:
                live
            case .idle:
                EmptyView()
            }
        }
        // Controls ignore touches while the cover slides away after Discard.
        .allowsHitTesting(tracker.isPresented)
        .onChange(of: tracker.phase, initial: true) {
            guard tracker.phase != .idle else { return }
            lastPhase = tracker.phase
            lastRun = tracker.finishedRun ?? lastRun
            lastAchievements = tracker.finishedAchievements
        }
        // Feedback lives here, on a view that survives the controls being swapped out.
        .sensoryFeedback(trigger: tracker.phase) { old, new in
            switch (old, new) {
            case (.running, .paused), (.paused, .running): .impact(weight: .medium)
            case (_, .finished): .success
            default: nil
            }
        }
        .sensoryFeedback(trigger: isLocked) { old, new in
            old != new ? .impact(weight: .light) : nil
        }
        .sensoryFeedback(.impact(weight: .light), trigger: tracker.splitEvents)
        .sensoryFeedback(.impact(weight: .heavy), trigger: tracker.coach.stepEvents)
        .sensoryFeedback(.success, trigger: tracker.goalEvents)
        .sensoryFeedback(.warning, trigger: tracker.autoPauseEvents)
        .confirmationDialog("Discard this run?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Run", role: .destructive) { tracker.discard() }
        } message: {
            Text("Nothing will be saved.")
        }
    }

    // MARK: Live

    private var unit: UnitSystem { tracker.unit }
    private var isTimeGoal: Bool { tracker.configuration.targetDuration != nil }
    private var isPaused: Bool { tracker.phase == .paused }

    private var live: some View {
        VStack(spacing: 0) {
            statusBar
                .padding(.horizontal, Space.x4)
                .padding(.top, Space.x2)

            Group {
                if hasCoachCard {
                    coachCard
                        .padding(.horizontal, Space.x4)
                        .padding(.top, 10)
                }
                if showingMap {
                    LiveRouteMap(route: tracker.route)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .padding(.horizontal, Space.x4)
                        .padding(.top, Space.x4)
                    LiveMapMetrics(distance: tracker.distance, elapsed: tracker.elapsed,
                                   averagePace: tracker.averagePace, unit: unit)
                        .padding(.horizontal, Space.x4)
                        .padding(.top, Space.x5)
                } else {
                    Spacer(minLength: Space.x4)
                    LiveMetrics(distance: tracker.distance, elapsed: tracker.elapsed, currentPace: tracker.currentPace,
                                averagePace: tracker.averagePace, calories: tracker.calories, unit: unit,
                                heroIsTime: isTimeGoal)
                        .padding(.horizontal, Space.x4)
                }
                Spacer(minLength: Space.x5)
            }
            // Locked: pans, zooms and taps on the content are ignored too.
            .allowsHitTesting(!isLocked)

            controls
                .frame(height: 140, alignment: .bottom)
                .padding(.bottom, Space.x6)
        }
        .background {
            if isPaused {
                BrandGlow(.wash).ignoresSafeArea()
            }
        }
        .animation(.snappy, value: showingMap)
        .animation(.snappy, value: tracker.phase)
    }

    private var statusBar: some View {
        HStack(spacing: Space.x2) {
            statusChip
            Spacer()
            RoundIconButton(showingMap ? "square.grid.2x2" : "map",
                            accessibilityLabel: showingMap ? "Show metrics" : "Show map") {
                showingMap.toggle()
            }
            .disabled(isLocked)
            if isPaused && !isLocked {
                DiscardCapsule { confirmingDiscard = true }
            } else {
                RoundIconButton(isLocked ? "lock.fill" : "lock",
                                accessibilityLabel: isLocked ? "Controls locked" : "Lock controls") {
                    isLocked = true
                }
                .disabled(isLocked)
            }
        }
        .frame(minHeight: Dimension.hitMin)
    }

    @ViewBuilder private var statusChip: some View {
        if isPaused {
            StatusChip(tracker.wasRestored ? "Run restored · paused" : "Paused", background: .trackSoft)
        } else if tracker.authorizationDenied {
            StatusChip("Location off", indicator: .warning)
        } else if tracker.accuracyLimited {
            StatusChip("Precise location off", indicator: .warning)
        } else if tracker.isAutoPaused {
            StatusChip("Auto-paused", background: .trackSoft)
        } else {
            GPSChip(quality: tracker.gpsQuality)
        }
    }

    // MARK: Coach

    private var hasCoachCard: Bool {
        tracker.coach.cursor != nil || tracker.goalProgress != nil || tracker.configuration.targetPace != nil
    }

    /// The workout step, else the distance or time goal, else the target pace.
    @ViewBuilder private var coachCard: some View {
        let coach = tracker.coach
        let config = tracker.configuration
        if let cursor = coach.cursor {
            WorkoutStepCard(workout: cursor.workout, stepIndex: cursor.index, remaining: coach.stepRemaining,
                            progress: coach.stepProgress, unit: unit, isPaused: isPaused,
                            paceStatus: coach.paceStatus)
        } else if let target = config.targetDistance, target > 0 {
            LiveGoalCard(goal: .distance(target), distance: tracker.distance, elapsed: tracker.elapsed, unit: unit,
                         paceStatus: isPaused ? nil : coach.paceStatus)
        } else if let target = config.targetDuration, target > 0 {
            LiveGoalCard(goal: .time(target), distance: tracker.distance, elapsed: tracker.elapsed, unit: unit,
                         paceStatus: isPaused ? nil : coach.paceStatus)
        } else if let pace = config.targetPace {
            TargetPaceCard(pace: pace, unit: unit, paceStatus: isPaused ? nil : coach.paceStatus)
        }
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        if isLocked {
            CaptionedRunControl("Hold to unlock") {
                HoldToConfirmButton(systemImage: "lock.open.fill", accessibilityLabel: "Hold to unlock",
                                    holdDuration: 0.8, fill: .ink, foreground: .surface) {
                    isLocked = false
                }
            }
        } else if isPaused {
            HStack(spacing: 64) {
                CaptionedRunControl("Hold to finish") {
                    HoldToConfirmButton(confirmationTitle: "Finish run?") { tracker.finish(in: context) }
                }
                CaptionedRunControl("Resume") {
                    RunControlButton(.resume) { tracker.resume() }
                }
            }
        } else {
            RunControlButton(.pause) { tracker.pause() }
        }
    }

    // MARK: Countdown copy

    /// What this run is, on a chip beside GPS: the workout, or the distance or time goal.
    private var countdownGoal: (title: String, dot: Color?)? {
        let config = tracker.configuration
        if let workout = config.workout {
            return (config.workoutName ?? workout.name, WorkoutStep.Kind.run.color)
        }
        if let meters = config.targetDistance, meters > 0 {
            return (LiveGoalCard.distanceName(meters, unit: unit), nil)
        }
        if let seconds = config.targetDuration, seconds > 0 {
            return (LiveGoalCard.timeName(seconds), nil)
        }
        return nil
    }

    /// "Warm-up first: 10 min easy. The coach calls every step."
    private var countdownMessage: String {
        let config = tracker.configuration
        let voice = StrideSettings.bool(StrideSettings.voiceCoach)
        if let workout = config.workout, let first = workout.steps.first {
            let lead = first.kind == .warmup
                ? "Warm-up first: \(WorkoutBlueprint.text(for: first.goal, unit: unit)) easy."
                : "First up: \(WorkoutStepCard.title(for: first, unit: unit))."
            return voice ? "\(lead) The coach calls every step." : lead
        }
        var parts: [String] = []
        if let meters = config.targetDistance, meters > 0 {
            parts.append("Goal: \(LiveGoalCard.distanceName(meters, unit: unit)).")
        } else if let seconds = config.targetDuration, seconds > 0 {
            parts.append("Goal: \(LiveGoalCard.timeName(seconds)).")
        } else {
            parts.append("Run at your own pace.")
        }
        if let pace = config.targetPace {
            parts.append("Hold \(RunFormat.pace(pace * unit.metersPerUnit / 1_000)) \(unit.paceSymbol).")
        }
        if voice { parts.append("The coach calls your splits.") }
        return parts.joined(separator: " ")
    }
}

// MARK: - Countdown

private struct CountdownView: View {
    let number: Int
    let gpsQuality: RunTracker.GPSQuality
    let goal: (title: String, dot: Color?)?
    let message: String
    let onSkip: () -> Void
    let onCancel: () -> Void
    /// The ring, emptying second by second toward the start.
    @State private var arc = 1.0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Space.x2) {
                GPSChip(quality: gpsQuality, background: Color.surfaceRaised.opacity(0.8))
                if let goal {
                    StatusChip(goal.title, indicator: goal.dot, background: Color.surfaceRaised.opacity(0.8))
                }
            }
            .padding(.top, Space.x3)

            Spacer(minLength: Space.x5)

            ZStack {
                Circle()
                    .stroke(Color.ink.opacity(0.1), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: arc)
                    .stroke(Color.track, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(number)")
                    .font(.system(size: 200, weight: .heavy).width(.expanded))
                    .monospacedDigit()
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: number)
            }
            .frame(width: 264, height: 264)
            .padding(Space.x2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Starting in \(number)")
            .accessibilityAddTraits(.updatesFrequently)

            VStack(spacing: Space.x2) {
                Text("Get ready")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.ink)
                    .accessibilityAddTraits(.isHeader)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            .padding(.top, Space.x6)

            Spacer(minLength: Space.x5)

            HStack(spacing: Space.x3) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.strideSecondary)
                Button("Start now", action: onSkip)
                    .buttonStyle(.strideSecondary)
                    .accessibilityHint("Skips the rest of the countdown")
            }
        }
        .padding(.horizontal, Space.x4)
        .padding(.bottom, Space.x4)
        .background {
            BrandGlow(.spotlight).ignoresSafeArea()
        }
        .sensoryFeedback(.impact(weight: .heavy), trigger: number)
        .onChange(of: number, initial: true) { _, number in
            withAnimation(.linear(duration: 1)) { arc = Double(max(number - 1, 0)) / 3 }
        }
    }
}

// MARK: - Status bar pieces

struct GPSChip: View {
    let quality: RunTracker.GPSQuality
    var background: Color = .surfaceRaised

    var body: some View {
        switch quality {
        case .searching: StatusChip("Searching for GPS", indicator: .lineStrong, background: background)
        case .weak: StatusChip("GPS weak", indicator: .warning, background: background)
        case .strong: StatusChip("GPS strong", indicator: .success, background: background)
        }
    }
}

/// Discard, beside the map button while paused.
private struct DiscardCapsule: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Discard")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.danger)
                .padding(.horizontal, 14)
                .frame(minHeight: Dimension.hitMin)
                .background(Color.surfaceRaised, in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Discard run")
    }
}

/// A round run control with a line under it: its name ("Hold to finish", "Resume"), which VoiceOver
/// skips since the control says it, or a note VoiceOver reads too (`isNote`).
struct CaptionedRunControl<Control: View>: View {
    let caption: String
    let isNote: Bool
    let control: Control

    init(_ caption: String, isNote: Bool = false, @ViewBuilder control: () -> Control) {
        self.caption = caption
        self.isNote = isNote
        self.control = control()
    }

    var body: some View {
        VStack(spacing: 14) {
            control
            Text(caption)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
                .multilineTextAlignment(.center)
                .accessibilityHidden(!isNote)
        }
    }
}

// MARK: - Metrics

/// The live numbers: distance (or time, for a time goal) large, then time or distance, current
/// pace, average pace and heart rate in a 2 × 2 grid. Runs without heart rate (iPhone) show
/// calories in its place; with heart rate, calories go on a line underneath.
struct LiveMetrics: View {
    let distance: Double
    let elapsed: TimeInterval
    let currentPace: Double?
    let averagePace: Double?
    let calories: Double
    let unit: UnitSystem
    let heroIsTime: Bool
    /// "171", or "--" while unknown. Nil for runs without heart rate.
    var heartRate: String? = nil
    var zone: HeartRateZone? = nil

    private var distanceText: String { RunFormat.distance(distance, unit: unit) }
    private var caloriesText: String { "\(Int(calories))" }

    var body: some View {
        VStack(spacing: 0) {
            if heroIsTime {
                StatTile("Time", value: RunFormat.duration(elapsed), size: .hero, alignment: .center)
            } else {
                StatTile("Distance", value: distanceText, unit: unit.distanceSymbol, size: .hero, alignment: .center)
            }

            DividedGrid(columns: 2, dividers: .rows, alignment: .center,
                        cellPadding: EdgeInsets(top: Space.x4, leading: Space.x1, bottom: Space.x4, trailing: Space.x1),
                        fill: nil) {
                if heroIsTime {
                    StatTile("Distance", value: distanceText, unit: unit.distanceSymbol, size: .large, alignment: .center)
                } else {
                    StatTile("Time", value: RunFormat.duration(elapsed), size: .large, alignment: .center)
                }
                StatTile("Pace", value: RunFormat.pace(currentPace), unit: unit.paceSymbol, size: .large, alignment: .center)
                StatTile("Avg pace", value: RunFormat.pace(averagePace), unit: unit.paceSymbol, size: .large, alignment: .center)
                if let heartRate {
                    StatTile("Heart rate", value: heartRate, unit: "bpm", size: .large, alignment: .center) {
                        if let zone { ZoneChip(zone) }
                    }
                } else {
                    StatTile("Calories", value: caloriesText, unit: "kcal", size: .large, alignment: .center)
                }
            }
            // 24pt below the big number: the first row's own 16pt padding plus 8.
            .padding(.top, Space.x2)

            if heartRate != nil {
                HStack(spacing: Space.x2) {
                    Text("Calories").metricLabelStyle()
                    Text("\(caloriesText) kcal")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.ink)
                        .contentTransition(.numericText())
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Under the map: distance, time and average pace in three columns.
struct LiveMapMetrics: View {
    let distance: Double
    let elapsed: TimeInterval
    let averagePace: Double?
    let unit: UnitSystem

    var body: some View {
        HStack(alignment: .top, spacing: Space.x1) {
            StatTile("Distance", value: RunFormat.distance(distance, unit: unit), unit: unit.distanceSymbol, size: .medium)
            StatTile("Time", value: RunFormat.duration(elapsed), size: .medium)
            StatTile("Avg pace", value: RunFormat.pace(averagePace), unit: unit.paceSymbol, size: .medium)
        }
    }
}

// MARK: - Coach cards

/// The card at the top of the live run: a small overline with an optional color dot, a title, an
/// amount at the trailing end ("320 m to go"), then bars and a footer line.
struct LiveCoachCard<Trailing: View, Content: View, Footer: View>: View {
    let overline: String
    let dot: Color?
    let title: String
    let trailing: Trailing
    let content: Content
    let footer: Footer

    init(overline: String, dot: Color? = nil, title: String,
         @ViewBuilder trailing: () -> Trailing, @ViewBuilder content: () -> Content,
         @ViewBuilder footer: () -> Footer) {
        self.overline = overline
        self.dot = dot
        self.title = title
        self.trailing = trailing()
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(alignment: .bottom, spacing: Space.x3) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.x2) {
                        if let dot {
                            Circle().fill(dot).frame(width: 10, height: 10)
                        }
                        Text(overline).metricLabelStyle()
                    }
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                trailing
            }
            content
            footer
        }
        .padding(.top, 14)
        .padding(.horizontal, Space.x4)
        .padding(.bottom, Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .combine)
    }
}

/// "320 m to go": the number in the metric face, the words muted.
private struct RemainingAmount: View {
    let value: String
    let label: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
            Text(value)
                .font(.metricMedium)
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(.ink)
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.inkMuted)
        }
        .lineLimit(1)
        .fixedSize()
    }
}

/// The step being run: which one, what it asks, how much is left, the whole workout below with
/// this step filling, and what comes next. Shared by iPhone runs and runs mirrored from Apple Watch.
struct WorkoutStepCard: View {
    let workout: Workout
    /// The current step; `workout.steps.count` once every step is done.
    let stepIndex: Int
    let remaining: WorkoutStep.Goal?
    /// 0…1 through the current step.
    let progress: Double
    let unit: UnitSystem
    var isPaused = false
    var paceStatus: PaceGuard.Status? = nil

    private var step: WorkoutStep? {
        workout.steps.indices.contains(stepIndex) ? workout.steps[stepIndex] : nil
    }

    private var next: WorkoutStep? {
        workout.steps.indices.contains(stepIndex + 1) ? workout.steps[stepIndex + 1] : nil
    }

    var body: some View {
        if let step {
            LiveCoachCard(overline: overline(step), dot: step.kind.color, title: Self.title(for: step, unit: unit)) {
                if let amount = remainingAmount(step) {
                    RemainingAmount(value: amount.value, label: amount.label)
                }
            } content: {
                VStack(spacing: 6) {
                    TrackBar(progress: progress, tint: step.kind.color, height: 8)
                        .accessibilityLabel("Step progress")
                    StepStrip(steps: workout.steps, height: 4, currentStep: stepIndex, currentProgress: progress)
                }
            } footer: {
                HStack(spacing: Space.x2) {
                    Group {
                        if let next {
                            Text("Next: \(Text(Self.nextText(next, unit: unit)).fontWeight(.semibold).foregroundStyle(.ink))")
                        } else {
                            Text("Last step")
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .lineLimit(1)
                    Spacer(minLength: 0)
                    if isPaused {
                        StatusChip(pausedText(step), background: .surfaceSunken)
                    } else if let paceStatus {
                        PaceStatusChip(status: paceStatus, unit: unit, background: .surfaceSunken)
                    }
                }
            }
            .animation(.snappy, value: progress)
        } else {
            LiveCoachCard(overline: "Workout complete", dot: .success, title: "Keep going or finish") {
                EmptyView()
            } content: {
                StepStrip(steps: workout.steps, height: 4, currentStep: workout.steps.count)
            } footer: {
                EmptyView()
            }
        }
    }

    /// "Rep 3 of 6" for the work intervals, the step's name otherwise.
    private func overline(_ step: WorkoutStep) -> String {
        if let number = workout.runNumber(of: step), workout.runStepCount > 1 {
            return "Rep \(number) of \(workout.runStepCount)"
        }
        return step.kind.title
    }

    /// "800 m at 4'45" /km", "4 min fast", "90 s easy".
    static func title(for step: WorkoutStep, unit: UnitSystem) -> String {
        let amount = WorkoutBlueprint.text(for: step.goal, unit: unit)
        switch step.kind {
        case .run:
            if let pace = step.targetPace {
                return "\(amount) at \(RunFormat.pace(pace * unit.metersPerUnit / 1_000)) \(unit.paceSymbol)"
            }
            // No target: plan easy and long runs are single run steps too, so no "fast" here.
            return amount
        case .warmup, .recover, .cooldown:
            return "\(amount) easy"
        }
    }

    /// "Recover · 90 s".
    static func nextText(_ step: WorkoutStep, unit: UnitSystem) -> String {
        "\(step.kind.title) · \(WorkoutBlueprint.text(for: step.goal, unit: unit))"
    }

    /// Left in the step, rounded up so it reads 0 only once the step is done: "1:25 to go", "320 m to go".
    private func remainingAmount(_ step: WorkoutStep) -> (value: String, label: String)? {
        switch remaining {
        case .time(let seconds):
            return (RunFormat.duration(seconds.rounded(.up)), "to go")
        case .distance(let meters):
            // Meters when the step itself is in meters: a 400 m repeat counts down in meters in miles too.
            let inMeters = unit == .metric ? meters < 1_000 : WorkoutBlueprint.text(for: step.goal, unit: unit).hasSuffix(" m")
            if inMeters {
                return ("\(Int(meters.rounded(.up)))", "m to go")
            }
            let value = (meters / unit.metersPerUnit * 100).rounded(.up) / 100 * unit.metersPerUnit
            return (RunFormat.distance(value, unit: unit), "\(unit.distanceSymbol) to go")
        case nil:
            return nil
        }
    }

    /// "Paused at 480 m" or "Paused at 1:30": how far into the step.
    private func pausedText(_ step: WorkoutStep) -> String {
        switch (step.goal, remaining) {
        case (.distance(let total), .distance(let left)?):
            return "Paused at \(WorkoutBlueprint.text(for: .distance(max(total - left, 0)), unit: unit))"
        case (.time(let total), .time(let left)?):
            return "Paused at \(RunFormat.duration(max(total - left, 0)))"
        default:
            return "Paused"
        }
    }
}

/// A distance or time goal: how much is left, and a bar that turns `success` once it's reached.
struct LiveGoalCard: View {
    enum Goal {
        /// Meters.
        case distance(Double)
        /// Seconds.
        case time(TimeInterval)
    }

    let goal: Goal
    let distance: Double
    let elapsed: TimeInterval
    let unit: UnitSystem
    /// The goal's own name, e.g. from Apple Watch ("10 km").
    var name: String? = nil
    var paceStatus: PaceGuard.Status? = nil

    private var progress: Double {
        switch goal {
        case .distance(let target): target > 0 ? distance / target : 0
        case .time(let target): target > 0 ? elapsed / target : 0
        }
    }

    private var isReached: Bool { progress >= 1 }

    var body: some View {
        LiveCoachCard(overline: overline, title: title) {
            if isReached {
                Label("Reached", systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.success)
            } else {
                RemainingAmount(value: remainingValue, label: remainingLabel)
            }
        } content: {
            TrackBar(progress: progress, tint: isReached ? .success : .track, height: 8)
                .accessibilityLabel("Goal progress")
        } footer: {
            if let paceStatus {
                HStack {
                    Spacer(minLength: 0)
                    PaceStatusChip(status: paceStatus, unit: unit, background: .surfaceSunken)
                }
            }
        }
        .animation(.snappy, value: progress)
    }

    private var overline: String {
        switch goal {
        case .distance: "Distance goal"
        case .time: "Time goal"
        }
    }

    private var title: String {
        if let name, !name.isEmpty { return name }
        switch goal {
        case .distance(let meters): return Self.distanceName(meters, unit: unit)
        case .time(let seconds): return Self.timeName(seconds)
        }
    }

    private var remainingValue: String {
        switch goal {
        case .distance(let target): RunFormat.distance(max(target - distance, 0), unit: unit)
        case .time(let target): RunFormat.duration(max(target - elapsed, 0).rounded(.up))
        }
    }

    private var remainingLabel: String {
        switch goal {
        case .distance: "\(unit.distanceSymbol) to go"
        case .time: "to go"
        }
    }

    /// "5 km", "3.1 mi", "Half marathon": race distances by name, others in the runner's unit.
    static func distanceName(_ meters: Double, unit: UnitSystem) -> String {
        if abs(meters - 21_097.5) < 1 { return "Half marathon" }
        if abs(meters - 42_195) < 1 { return "Marathon" }
        if unit == .imperial {
            if abs(meters - 5_000) < 1 { return "5K" }
            if abs(meters - 10_000) < 1 { return "10K" }
        }
        let value = meters / unit.metersPerUnit
        return "\(value.formatted(.number.precision(.fractionLength(0...2)))) \(unit.distanceSymbol)"
    }

    /// "30 min", "90 min": as the run setup's chips say it.
    static func timeName(_ seconds: TimeInterval) -> String {
        "\(Int((seconds / 60).rounded())) min"
    }
}

/// A free run with a target pace: the pace to hold, and how the runner is doing against it.
private struct TargetPaceCard: View {
    /// Seconds per kilometer.
    let pace: Double
    let unit: UnitSystem
    let paceStatus: PaceGuard.Status?

    var body: some View {
        LiveCoachCard(overline: "Target pace",
                  title: "\(RunFormat.pace(pace * unit.metersPerUnit / 1_000)) \(unit.paceSymbol)") {
            if let paceStatus {
                PaceStatusChip(status: paceStatus, unit: unit, background: .surfaceSunken)
            }
        } content: {
            EmptyView()
        } footer: {
            EmptyView()
        }
    }
}

/// On target, or how far off it: words first, color only reinforces.
struct PaceStatusChip: View {
    let status: PaceGuard.Status
    let unit: UnitSystem
    var background: Color = .surfaceRaised

    var body: some View {
        switch status {
        case .onPace:
            StatusChip("On target pace", indicator: .success, background: background)
        case .tooSlow(let seconds):
            StatusChip("Speed up · \(Int(seconds.rounded())) s\(unit.paceSymbol) behind", indicator: .warning, background: background)
        case .tooFast(let seconds):
            StatusChip("Ease off · \(Int(seconds.rounded())) s\(unit.paceSymbol) ahead", indicator: .lane, background: background)
        }
    }
}
