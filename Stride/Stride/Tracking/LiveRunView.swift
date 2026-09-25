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
                CountdownView(number: number, onSkip: { tracker.startNow() }, onCancel: { tracker.cancelCountdown() })
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

    private var live: some View {
        VStack(spacing: 0) {
            statusBar
                .padding(.horizontal, Space.x4)
                .padding(.top, Space.x2)

            Group {
            if showingMap {
                LiveRouteMap(route: tracker.route)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .padding(Space.x4)
                HStack(spacing: Space.x3) {
                    MetricView("Distance", value: RunFormat.distance(tracker.distance, unit: unit), unit: unit.distanceSymbol, size: .small)
                    MetricView("Time", value: RunFormat.duration(tracker.elapsed), size: .small)
                    MetricView("Avg pace", value: RunFormat.pace(tracker.averagePace), unit: unit.paceSymbol, size: .small)
                }
                .padding(.horizontal, Space.x4)
                .padding(.bottom, Space.x5)
            } else {
                Spacer(minLength: Space.x5)
                primaryMetric
                Spacer(minLength: Space.x5)
                metricGrid
                    .padding(.horizontal, Space.x4)
                coachSection
                    .padding(.horizontal, Space.x4)
                    .padding(.top, Space.x5)
                Spacer(minLength: Space.x5)
            }
            }
            // Locked: pans, zooms and taps on the content are ignored too.
            .allowsHitTesting(!isLocked)

            controls
                .frame(minHeight: 176, alignment: .top)
                .padding(.bottom, Space.x4)
        }
        .animation(.snappy, value: showingMap)
        .animation(.snappy, value: tracker.phase)
    }

    private var statusBar: some View {
        HStack(spacing: Space.x2) {
            if tracker.phase == .paused {
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
            Spacer()
            iconButton(showingMap ? "number" : "map.fill", label: showingMap ? "Show metrics" : "Show map") {
                showingMap.toggle()
            }
            .disabled(isLocked)
            iconButton(isLocked ? "lock.fill" : "lock", label: isLocked ? "Controls locked" : "Lock controls") {
                isLocked = true
            }
            .disabled(isLocked)
        }
    }

    private var primaryMetric: some View {
        Group {
            if isTimeGoal {
                MetricView("Time", value: RunFormat.duration(tracker.elapsed), size: .hero, alignment: .center)
            } else {
                MetricView("Distance", value: RunFormat.distance(tracker.distance, unit: unit), unit: unit.distanceSymbol, size: .hero, alignment: .center)
            }
        }
        .padding(.horizontal, Space.x4)
    }

    private var metricGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.x3), GridItem(.flexible())], spacing: Space.x5) {
            if isTimeGoal {
                MetricView("Distance", value: RunFormat.distance(tracker.distance, unit: unit), unit: unit.distanceSymbol, alignment: .center)
            } else {
                MetricView("Time", value: RunFormat.duration(tracker.elapsed), alignment: .center)
            }
            MetricView("Avg pace", value: RunFormat.pace(tracker.averagePace), unit: unit.paceSymbol, alignment: .center)
            MetricView("Current pace", value: RunFormat.pace(tracker.currentPace), unit: unit.paceSymbol, alignment: .center)
            MetricView("Calories", value: "\(Int(tracker.calories))", unit: "kcal", alignment: .center)
        }
    }

    /// The current workout step, or the goal bar; plus the target-pace status when there's a target.
    @ViewBuilder private var coachSection: some View {
        let coach = tracker.coach
        VStack(spacing: Space.x3) {
            if let cursor = coach.cursor {
                if let step = cursor.currentStep {
                    WorkoutStepCard(step: step, workout: cursor.workout, next: cursor.nextStep,
                                    remaining: coach.stepRemaining, progress: coach.stepProgress, unit: unit)
                } else {
                    StatusChip("Workout complete · keep going or finish", indicator: .success)
                }
            } else {
                goalBar
            }
            if let status = coach.paceStatus {
                PaceStatusChip(status: status, unit: unit)
            }
        }
    }

    @ViewBuilder private var goalBar: some View {
        if let progress = tracker.goalProgress {
            VStack(alignment: .leading, spacing: Space.x2) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.surfaceSunken)
                        Capsule()
                            .fill(progress >= 1 ? Color.success : Color.track)
                            .frame(width: geo.size.width * min(progress, 1))
                    }
                }
                .frame(height: 8)
                Text(goalText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.inkMuted)
            }
            .animation(.snappy, value: progress)
        }
    }

    private var goalText: String {
        let config = tracker.configuration
        if let target = config.targetDistance {
            if tracker.distance >= target { return "Goal reached" }
            return "\(RunFormat.distance(tracker.distance, unit: unit)) of \(RunFormat.distance(target, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
        }
        if let target = config.targetDuration {
            if tracker.elapsed >= target { return "Goal reached" }
            return "\(RunFormat.duration(target - tracker.elapsed)) to go"
        }
        return ""
    }

    @ViewBuilder private var controls: some View {
        if isLocked {
            VStack(spacing: Space.x2) {
                HoldToConfirmButton(systemImage: "lock.open.fill", accessibilityLabel: "Hold to unlock",
                                    holdDuration: 0.8, fill: .ink, foreground: .surface) {
                    isLocked = false
                }
                Text("Hold to unlock").font(.caption).foregroundStyle(.inkMuted)
            }
        } else if tracker.phase == .paused {
            VStack(spacing: Space.x4) {
                HStack(spacing: Space.x7) {
                    VStack(spacing: Space.x2) {
                        HoldToConfirmButton(confirmationTitle: "Finish run?") { tracker.finish(in: context) }
                        Text("Hold to finish").font(.caption).foregroundStyle(.inkMuted)
                    }
                    VStack(spacing: Space.x2) {
                        RunControlButton(.resume) { tracker.resume() }
                        Text("Resume").font(.caption).foregroundStyle(.inkMuted)
                    }
                }
                Button("Discard run") { confirmingDiscard = true }
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            }
        } else {
            RunControlButton(.pause) { tracker.pause() }
        }
    }

    private func iconButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(.ink)
                .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                .background(Color.surfaceRaised, in: Circle())
        }
        .accessibilityLabel(label)
    }
}

// MARK: - Countdown

private struct CountdownView: View {
    let number: Int
    let onSkip: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: Space.x4) {
            Spacer()
            Text("\(number)")
                .font(.system(size: 200, weight: .heavy).width(.expanded))
                .monospacedDigit()
                .foregroundStyle(.track)
                .contentTransition(.numericText(countsDown: true))
                .animation(.snappy, value: number)
            Text("Get ready")
                .font(.title2.bold())
                .foregroundStyle(.ink)
            Spacer()
            Button("Start now", action: onSkip)
                .buttonStyle(.stridePrimary)
            Button("Cancel", action: onCancel)
                .buttonStyle(.strideSecondary)
        }
        .padding(Space.x4)
        .sensoryFeedback(.impact(weight: .heavy), trigger: number)
    }
}

// MARK: - GPS chip

struct GPSChip: View {
    let quality: RunTracker.GPSQuality

    var body: some View {
        switch quality {
        case .searching: StatusChip("Searching for GPS", indicator: .lineStrong)
        case .weak: StatusChip("GPS weak", indicator: .warning)
        case .strong: StatusChip("GPS strong", indicator: .success)
        }
    }
}

// MARK: - Coach

/// The step being run: what it is, how much is left, and what comes next.
struct WorkoutStepCard: View {
    let step: WorkoutStep
    let workout: Workout
    let next: WorkoutStep?
    let remaining: WorkoutStep.Goal?
    let progress: Double
    let unit: UnitSystem

    private var color: Color {
        switch step.kind {
        case .run: .track
        case .recover: .lane
        case .warmup, .cooldown: .inkMuted
        }
    }

    private var title: String {
        if let number = workout.runNumber(of: step), workout.runStepCount > 1 {
            return "\(step.kind.title) · \(number) of \(workout.runStepCount)"
        }
        return step.kind.title
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: Space.x2) {
                    Circle().fill(color).frame(width: 10, height: 10)
                    Text(title).font(.headline).foregroundStyle(.ink)
                }
                Spacer()
                Text(remainingText)
                    .font(.metricSmall)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(.ink)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surfaceSunken)
                    Capsule().fill(color).frame(width: geo.size.width * min(max(progress, 0), 1))
                }
            }
            .frame(height: 8)
            if let next {
                Text("Next: \(next.kind.title) \(goalText(next.goal))")
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
            }
        }
        .padding(Space.x4)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .combine)
        .animation(.snappy, value: progress)
    }

    private var remainingText: String {
        switch remaining {
        // Rounded up: the card reads 0 only once the step is actually done.
        case .time(let seconds): RunFormat.duration(seconds.rounded(.up))
        case .distance(let meters):
            if meters < 1_000 && unit == .metric {
                "\(Int(meters.rounded(.up))) m"
            } else {
                "\(RunFormat.distance((meters / unit.metersPerUnit * 100).rounded(.up) / 100 * unit.metersPerUnit, unit: unit)) \(unit.distanceSymbol)"
            }
        case nil: RunFormat.empty
        }
    }

    private func goalText(_ goal: WorkoutStep.Goal) -> String {
        switch goal {
        case .time(let seconds): seconds < 60 ? "\(Int(seconds)) s" : RunFormat.duration(seconds)
        case .distance(let meters): meters < 1_000 && unit == .metric ? "\(Int(meters)) m" : "\(RunFormat.distance(meters, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
        }
    }
}

/// On target, or how far off it: words first, color only reinforces.
struct PaceStatusChip: View {
    let status: PaceGuard.Status
    let unit: UnitSystem

    var body: some View {
        switch status {
        case .onPace:
            StatusChip("On target pace", indicator: .success)
        case .tooSlow(let seconds):
            StatusChip("Speed up · \(Int(seconds.rounded())) s\(unit.paceSymbol) behind", indicator: .warning)
        case .tooFast(let seconds):
            StatusChip("Ease off · \(Int(seconds.rounded())) s\(unit.paceSymbol) ahead", indicator: .lane)
        }
    }
}
