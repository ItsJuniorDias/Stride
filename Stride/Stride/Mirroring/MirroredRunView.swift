import SwiftUI
import StrideKit
import StrideUI

/// A run happening on Apple Watch, live on iPhone. The controls act on the Watch's workout.
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

    /// Only the metrics redraw every second; the controls stay put so a hold isn't interrupted.
    private var live: some View {
        VStack(spacing: 0) {
            statusBar
                .padding(.horizontal, Space.x4)
                .padding(.top, Space.x2)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                metrics(at: context.date)
            }

            controls
                .frame(minHeight: 176, alignment: .top)
                .padding(.bottom, Space.x4)
        }
        .animation(.snappy, value: showingMap)
        .animation(.snappy, value: workout.phase)
    }

    @ViewBuilder private func metrics(at date: Date) -> some View {
        let elapsed = workout.elapsed(at: date)
        let distance = snapshot?.distance ?? 0
        VStack(spacing: 0) {
            if showingMap {
                LiveRouteMap(coordinates: workout.route.coordinates)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .padding(Space.x4)
                HStack(spacing: Space.x3) {
                    MetricView("Distance", value: RunFormat.distance(distance, unit: unit), unit: unit.distanceSymbol, size: .small)
                    MetricView("Time", value: RunFormat.duration(elapsed), size: .small)
                    MetricView("Heart rate", value: heartRateText, unit: "bpm", size: .small)
                }
                .padding(.horizontal, Space.x4)
                .padding(.bottom, Space.x5)
            } else {
                Spacer(minLength: Space.x5)
                Group {
                    if isTimeGoal {
                        MetricView("Time", value: RunFormat.duration(elapsed), size: .hero, alignment: .center)
                    } else {
                        MetricView("Distance", value: RunFormat.distance(distance, unit: unit), unit: unit.distanceSymbol, size: .hero, alignment: .center)
                    }
                }
                .padding(.horizontal, Space.x4)
                Spacer(minLength: Space.x5)
                LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.x3), GridItem(.flexible())], spacing: Space.x5) {
                    if isTimeGoal {
                        MetricView("Distance", value: RunFormat.distance(distance, unit: unit), unit: unit.distanceSymbol, alignment: .center)
                    } else {
                        MetricView("Time", value: RunFormat.duration(elapsed), alignment: .center)
                    }
                    MetricView("Avg pace", value: RunFormat.pace(averagePace), unit: unit.paceSymbol, alignment: .center)
                    MetricView("Current pace", value: RunFormat.pace(currentPace), unit: unit.paceSymbol, alignment: .center)
                    MetricView("Heart rate", value: heartRateText, unit: "bpm", alignment: .center)
                }
                .padding(.horizontal, Space.x4)
                if let zone {
                    StatusChip("Zone \(zone.rawValue) · \(zone.name)", indicator: zone.color)
                        .padding(.top, Space.x4)
                }
                Group {
                    if let progress = snapshot?.workoutProgress {
                        stepCard(progress, elapsed: elapsed)
                    } else {
                        goalBar(distance: distance, elapsed: elapsed)
                    }
                }
                .padding(.horizontal, Space.x4)
                .padding(.top, Space.x5)
                Spacer(minLength: Space.x5)
            }
        }
    }

    private var statusBar: some View {
        HStack(spacing: Space.x2) {
            Group {
                if !workout.isLinked {
                    StatusChip("Disconnected from Apple Watch", indicator: .warning)
                } else if !workout.isConnected {
                    StatusChip(workout.phase == .paused ? "Paused · reconnecting" : "Reconnecting to Apple Watch", indicator: .warning)
                } else if workout.phase == .paused {
                    StatusChip("Paused on Apple Watch", background: .trackSoft)
                } else {
                    StatusChip("Live from Apple Watch", indicator: .success)
                }
            }
            Spacer()
            Button {
                showingMap.toggle()
            } label: {
                Image(systemName: showingMap ? "number" : "map.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
                    .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                    .background(Color.surfaceRaised, in: Circle())
            }
            .accessibilityLabel(showingMap ? "Show metrics" : "Show map")
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

    @ViewBuilder private func goalBar(distance: Double, elapsed: TimeInterval) -> some View {
        let progress: Double? = {
            if let target = snapshot?.goalDistance, target > 0 { return distance / target }
            if let target = snapshot?.goalDuration, target > 0 { return elapsed / target }
            return nil
        }()
        if let progress {
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
                Text(goalText(distance: distance, elapsed: elapsed, progress: progress))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.inkMuted)
            }
        }
    }

    /// The interval step the Watch is on, as the iPhone's own runs show it. A timed step counts down
    /// between snapshots with the clock; a distance step moves with the next snapshot.
    @ViewBuilder private func stepCard(_ progress: MirrorWorkoutProgress, elapsed: TimeInterval) -> some View {
        if let step = progress.currentStep {
            let remaining = progress.remaining(after: elapsed - (snapshot?.elapsed ?? elapsed))
            WorkoutStepCard(step: step, workout: progress.workout, next: progress.nextStep,
                            remaining: remaining, progress: progress.progress(remaining: remaining), unit: unit)
        } else {
            StatusChip("Workout complete · keep going or finish", indicator: .success)
        }
    }

    private func goalText(distance: Double, elapsed: TimeInterval, progress: Double) -> String {
        if progress >= 1 { return "Goal reached" }
        if let target = snapshot?.goalDistance {
            return "\(RunFormat.distance(distance, unit: unit)) of \(RunFormat.distance(target, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
        }
        if let target = snapshot?.goalDuration {
            return "\(RunFormat.duration(target - elapsed)) to go"
        }
        return ""
    }

    @ViewBuilder private var controls: some View {
        if !workout.isLinked {
            VStack(spacing: Space.x3) {
                Button("Close") { workout.dismiss() }
                    .buttonStyle(.stridePrimary)
                Text("Your run continues on Apple Watch and will appear in Activities when it ends.")
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, Space.x4)
        } else if !workout.isConnected {
            VStack(spacing: Space.x2) {
                RunControlButton(workout.phase == .paused ? .resume : .pause) {}
                    .disabled(true)
                    .opacity(0.4)
                Text("Use your Apple Watch to control the run").font(.caption).foregroundStyle(.inkMuted)
            }
        } else if workout.phase == .paused {
            HStack(spacing: Space.x7) {
                VStack(spacing: Space.x2) {
                    HoldToConfirmButton(accessibilityLabel: "Hold to end on Apple Watch", confirmationTitle: "End run on Apple Watch?") {
                        workout.end()
                    }
                    Text("Hold to end").font(.caption).foregroundStyle(.inkMuted)
                }
                VStack(spacing: Space.x2) {
                    RunControlButton(.resume) { workout.resume() }
                    Text("Resume").font(.caption).foregroundStyle(.inkMuted)
                }
            }
        } else {
            VStack(spacing: Space.x2) {
                RunControlButton(.pause) { workout.pause() }
                Text("Controls your Apple Watch").font(.caption).foregroundStyle(.inkMuted)
            }
        }
    }

    // MARK: Finished

    private var finished: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44))
                .foregroundStyle(.success)
                .accessibilityHidden(true)
            Text("Run saved on Apple Watch")
                .font(.largeTitle.bold())
                .foregroundStyle(.ink)
            Text("It'll appear in Activities in a moment, with your route, splits and heart-rate zones.")
                .font(.body)
                .foregroundStyle(.inkMuted)
            if let snapshot {
                HStack(spacing: Space.x3) {
                    MetricTile("Distance", value: RunFormat.distance(snapshot.distance, unit: unit), unit: unit.distanceSymbol)
                    MetricTile("Time", value: RunFormat.duration(workout.elapsed(at: .now)))
                }
            }
            Spacer()
            Button("Done") { workout.dismiss() }
                .buttonStyle(.stridePrimary)
        }
        .padding(Space.x4)
    }
}
