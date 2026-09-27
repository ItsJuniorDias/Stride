import SwiftUI
import StrideKit
import StrideUI

/// A run happening on Apple Watch, live on iPhone, laid out like an iPhone run with the Watch's heart
/// rate. The controls act on the Watch's workout.
struct MirroredRunView: View {
    @Environment(MirroredWorkout.self) private var workout
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.maxHeartRate) private var maxHeartRate = HeartRateZone.defaultMaxHeartRate
    @State private var showingMap = false

    var body: some View {
        ZStack {
            Color.surface.ignoresSafeArea()
            if workout.phase == .ended {
                finished
            } else {
                live
            }
        }
        // Ignore touches while the cover slides away after Done or Close.
        .allowsHitTesting(workout.isPresented)
        .alert("Apple Watch", isPresented: Binding(get: { workout.controlError != nil }, set: { if !$0 { workout.clearControlError() } })) {
            Button("OK") {}
        } message: {
            Text(workout.controlError ?? "")
        }
        .sensoryFeedback(trigger: workout.phase) { old, new in
            switch (old, new) {
            case (.running, .paused), (.paused, .running): .impact(weight: .medium)
            case (_, .ended): .success
            default: nil
            }
        }
    }

    // MARK: Live

    private var snapshot: MirrorSnapshot? { workout.snapshot }
    private var isTimeGoal: Bool { snapshot?.goalDuration != nil }
    private var isPaused: Bool { workout.phase == .paused }

    /// Only the metrics redraw every second; the controls stay put so a hold isn't interrupted.
    private var live: some View {
        VStack(spacing: 0) {
            statusBar
                .padding(.horizontal, Space.x4)
                .padding(.top, Space.x2)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                content(at: context.date)
            }

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
        .animation(.snappy, value: workout.phase)
    }

    @ViewBuilder private func content(at date: Date) -> some View {
        let elapsed = workout.elapsed(at: date)
        let distance = snapshot?.distance ?? 0
        VStack(spacing: 0) {
            if hasCoachCard {
                coachCard(distance: distance, elapsed: elapsed)
                    .padding(.horizontal, Space.x4)
                    .padding(.top, 10)
            }
            if showingMap {
                LiveRouteMap(coordinates: workout.route.coordinates)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .padding(.horizontal, Space.x4)
                    .padding(.top, Space.x4)
                LiveMapMetrics(distance: distance, elapsed: elapsed, averagePace: averagePace, unit: unit)
                    .padding(.horizontal, Space.x4)
                    .padding(.top, Space.x5)
            } else {
                Spacer(minLength: Space.x4)
                LiveMetrics(distance: distance, elapsed: elapsed, currentPace: currentPace, averagePace: averagePace,
                            calories: snapshot?.calories ?? 0, unit: unit, heroIsTime: isTimeGoal,
                            heartRate: heartRateText, zone: zone)
                    .padding(.horizontal, Space.x4)
            }
            Spacer(minLength: Space.x5)
        }
    }

    private var statusBar: some View {
        HStack(spacing: Space.x2) {
            Group {
                if !workout.isLinked {
                    StatusChip("Disconnected from Apple Watch", indicator: .warning)
                } else if !workout.isConnected {
                    StatusChip(isPaused ? "Paused · reconnecting" : "Reconnecting to Apple Watch", indicator: .warning)
                } else if isPaused {
                    StatusChip("Paused on Apple Watch", background: .trackSoft)
                } else {
                    StatusChip("Live from Apple Watch", indicator: .success)
                }
            }
            Spacer()
            RoundIconButton(showingMap ? "square.grid.2x2" : "map",
                            accessibilityLabel: showingMap ? "Show metrics" : "Show map") {
                showingMap.toggle()
            }
        }
        .frame(minHeight: Dimension.hitMin)
    }

    // MARK: Coach

    private var hasCoachCard: Bool {
        snapshot?.workoutProgress != nil || (snapshot?.goalDistance ?? 0) > 0 || (snapshot?.goalDuration ?? 0) > 0
    }

    /// The interval step the Watch is on, as the iPhone's own runs show it, or the goal. A timed step
    /// counts down between snapshots with the clock; a distance step moves with the next snapshot.
    @ViewBuilder private func coachCard(distance: Double, elapsed: TimeInterval) -> some View {
        if let progress = snapshot?.workoutProgress {
            let remaining = progress.remaining(after: elapsed - (snapshot?.elapsed ?? elapsed))
            WorkoutStepCard(workout: progress.workout, stepIndex: progress.stepIndex, remaining: remaining,
                            progress: progress.progress(remaining: remaining), unit: unit, isPaused: isPaused)
        } else if let target = snapshot?.goalDistance, target > 0 {
            LiveGoalCard(goal: .distance(target), distance: distance, elapsed: elapsed, unit: unit, name: snapshot?.goalName)
        } else if let target = snapshot?.goalDuration, target > 0 {
            LiveGoalCard(goal: .time(target), distance: distance, elapsed: elapsed, unit: unit, name: snapshot?.goalName)
        }
    }

    // Live values are only shown while snapshots are arriving; stale ones would be misleading.

    private var heartRateText: String {
        guard workout.isConnected else { return RunFormat.empty }
        return snapshot?.heartRate.map { "\(Int($0))" } ?? RunFormat.empty
    }

    private var zone: HeartRateZone? {
        guard workout.isConnected else { return nil }
        return snapshot?.heartRate.flatMap { HeartRateZone.zone(for: $0, maxHeartRate: maxHeartRate) }
    }

    private var currentPace: Double? {
        guard workout.phase == .running, workout.isConnected, let speed = snapshot?.currentSpeed, speed > 0.5 else { return nil }
        return unit.metersPerUnit / speed
    }

    /// From one snapshot, so distance and time always belong together.
    private var averagePace: Double? {
        guard let snapshot else { return nil }
        return RunFormat.paceSeconds(distance: snapshot.distance, duration: snapshot.elapsed, unit: unit)
    }

    // MARK: Controls

    @ViewBuilder private var controls: some View {
        if !workout.isLinked {
            VStack(spacing: Space.x3) {
                Button("Close") { workout.dismiss() }
                    .buttonStyle(.stridePrimary)
                Text("Your run continues on Apple Watch and will appear in Activities when it ends.")
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Space.x4)
        } else if !workout.isConnected {
            CaptionedRunControl("Use your Apple Watch to control the run", isNote: true) {
                RunControlButton(isPaused ? .resume : .pause) {}
                    .disabled(true)
                    .opacity(0.4)
            }
            .padding(.horizontal, Space.x4)
        } else if isPaused {
            HStack(spacing: 64) {
                CaptionedRunControl("Hold to end") {
                    HoldToConfirmButton(accessibilityLabel: "Hold to end on Apple Watch", confirmationTitle: "End run on Apple Watch?") {
                        workout.end()
                    }
                }
                CaptionedRunControl("Resume") {
                    RunControlButton(.resume) { workout.resume() }
                }
            }
        } else {
            CaptionedRunControl("Controls your Apple Watch", isNote: true) {
                RunControlButton(.pause) { workout.pause() }
            }
        }
    }

    // MARK: Finished

    private var finished: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            Spacer()
            IconBadge("checkmark", style: .tinted(.success), size: 44)
            Text("Run saved on Apple Watch")
                .font(.largeTitle.bold())
                .foregroundStyle(.ink)
                .accessibilityAddTraits(.isHeader)
            Text("It'll appear in Activities in a moment, with your route, splits and heart-rate zones.")
                .font(.body)
                .foregroundStyle(.inkMuted)
            if let snapshot {
                DividedGrid(columns: 2) {
                    StatTile("Distance", value: RunFormat.distance(snapshot.distance, unit: unit),
                             unit: unit.distanceSymbol, size: .medium)
                    StatTile("Time", value: RunFormat.duration(workout.elapsed(at: .now)), size: .medium)
                }
            }
            Spacer()
            Button("Done") { workout.dismiss() }
                .buttonStyle(.stridePrimary)
        }
        .padding(Space.x4)
        .background(alignment: .topLeading) {
            BrandGlow(.corner).ignoresSafeArea()
        }
    }
}
