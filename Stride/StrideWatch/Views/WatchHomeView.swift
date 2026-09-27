import Foundation
import SwiftUI
import StrideKit
import StrideUI

/// Start list: a free run first, then distance and time goals, interval workouts (Pro), the week
/// against its goal and friends.
struct WatchHomeView: View {
    @Environment(WorkoutManager.self) private var workout
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    /// The week and friends, from iPhone.
    @State private var snapshot = WidgetStore.load()
    /// Stride Pro as iPhone last reported it. Pro is bought and restored on iPhone only.
    @AppStorage(WatchContext.proActive) private var isPro = false
    /// The workouts iPhone sent; the interval presets until it has.
    @AppStorage(WatchContext.workouts) private var workoutsData = Data()
    @AppStorage(WatchVoice.enabledKey) private var speaksSteps = true

    /// Plan sessions first, then the presets and the runner's own workouts, as iPhone ordered them.
    private var library: [Workout] {
        let all = WatchContext.decodeWorkouts(workoutsData) ?? IntervalPresets.all
        return all.filter { Self.isFromPlan($0) } + all.filter { !Self.isFromPlan($0) }
    }

    /// Neither a preset nor a workout the runner built: a training-plan session.
    private nonisolated static func isFromPlan(_ workout: Workout) -> Bool {
        !workout.id.hasPrefix("preset-") && !workout.id.hasPrefix(CustomWorkout.workoutIDPrefix)
    }

    private struct GoalOption: Identifiable {
        let value: String
        let unit: String
        let accessibilityLabel: String
        let goal: WorkoutManager.Goal

        var id: String { accessibilityLabel }
    }

    private var distanceGoals: [GoalOption] {
        [
            GoalOption(value: "5", unit: "km", accessibilityLabel: "Run 5 kilometers",
                       goal: .init(type: .distance, distance: 5_000, name: "5 km")),
            GoalOption(value: "10", unit: "km", accessibilityLabel: "Run 10 kilometers",
                       goal: .init(type: .distance, distance: 10_000, name: "10 km")),
            GoalOption(value: unit == .metric ? "21.1" : "13.1", unit: "Half", accessibilityLabel: "Run a half marathon",
                       goal: .init(type: .distance, distance: 21_097.5, name: "Half Marathon")),
        ]
    }

    private let timeGoals: [GoalOption] = [
        GoalOption(value: "30", unit: "min", accessibilityLabel: "Run for 30 minutes",
                   goal: .init(type: .time, duration: 1_800, name: "30 min")),
        GoalOption(value: "60", unit: "min", accessibilityLabel: "Run for 60 minutes",
                   goal: .init(type: .time, duration: 3_600, name: "60 min")),
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    // Access problems come first, where they're seen before a start button is tapped.
                    accessNotices

                    freeRun

                    WatchOverline("Goals", inset: 6)
                        .padding(.top, 10)
                    goalGrid

                    intervals

                    if let snapshot {
                        week(snapshot)
                        friends(snapshot)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 6)
                .padding(.bottom, 28)
            }
            .navigationTitle("Stride")
        }
        .task { await workout.requestAuthorization() }
        // New data from iPhone lands while the app is open, too.
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            let latest = WidgetStore.load()
            if latest != snapshot { snapshot = latest }
        }
    }

    // MARK: Access

    @ViewBuilder private var accessNotices: some View {
        if workout.isCheckingAccess {
            ProgressView("Checking Health access…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, Space.x2)
        }
        if let message = workout.authorizationError {
            notice(message, systemImage: "heart.slash")
        }
        if workout.locationDenied {
            notice("GPS off: no route or pace. Turn on Location for Stride in Settings.", systemImage: "location.slash")
        }
    }

    private func notice(_ message: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: Space.x2) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .semibold))
                .accessibilityHidden(true)
            Text(message)
                .watchFont(13)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(.warning)
        .padding(Space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchCard()
    }

    // MARK: Runs

    private var freeRun: some View {
        Button {
            Task { await workout.start(.init()) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "figure.run")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.onTrack)
                    .frame(width: 40, height: 40)
                    .background(Color.track, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Free run")
                        .watchFont(17, .semibold)
                        .foregroundStyle(.ink)
                    Text("Outdoor · no goal")
                        .watchFont(13)
                        .foregroundStyle(.inkMuted)
                }
                .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Space.x3)
            .padding(.vertical, 10)
            .frame(minHeight: 64)
        }
        .buttonStyle(WatchCardButtonStyle(fill: .trackSoft))
        .disabled(workout.isCheckingAccess)
        .accessibilityLabel("Start a free run")
    }

    /// 5 km, 10 km and the half on one row; 30 and 60 minutes on the next.
    private var goalGrid: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                ForEach(distanceGoals) { goalTile($0) }
            }
            HStack(spacing: 6) {
                ForEach(timeGoals) { goalTile($0) }
            }
        }
        .disabled(workout.isCheckingAccess)
    }

    private func goalTile(_ option: GoalOption) -> some View {
        Button {
            Task { await workout.start(option.goal) }
        } label: {
            VStack(spacing: 2) {
                Text(option.value)
                    .font(.watchMetric(18, weight: .heavy))
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(option.unit)
                    .watchFont(11, .semibold)
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(.inkMuted)
                    .lineLimit(1)
            }
            .padding(.horizontal, Space.x1)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(WatchCardButtonStyle())
        .accessibilityLabel(option.accessibilityLabel)
    }

    // MARK: Intervals

    /// Everyone sees the workouts; only Pro starts them. There's nothing to buy on the Watch.
    @ViewBuilder private var intervals: some View {
        HStack(spacing: 6) {
            WatchOverline("Intervals", inset: 6)
            if !isPro { TagBadge("Pro") }
        }
        .padding(.top, 10)

        if !isPro {
            VStack(alignment: .leading, spacing: 2) {
                Text("Get Stride Pro on iPhone")
                    .watchFont(15, .semibold)
                    .foregroundStyle(.ink)
                Text("Steps, haptics and voice cues on your wrist.")
                    .watchFont(12)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, Space.x3)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .watchCard()
            .accessibilityElement(children: .combine)
        }

        ForEach(library) { item in
            workoutRow(item)
        }

        if isPro {
            Toggle("Spoken steps", isOn: $speaksSteps)
                .watchFont(15, .medium)
                .tint(.track)
                .padding(.horizontal, Space.x3)
                .frame(minHeight: 48)
                .watchCard()
        }
    }

    /// The name (with Plan on a plan session), what it is, and its shape: runs tall in yellow,
    /// recoveries low in blue, warm-up and cool-down gray.
    private func workoutRow(_ item: Workout) -> some View {
        Button {
            Task { await workout.start(.init(type: .intervals, name: item.name, workout: item)) }
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .watchFont(15, .semibold)
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                    if Self.isFromPlan(item) {
                        planBadge
                    }
                }
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .watchFont(12)
                        .foregroundStyle(.inkMuted)
                        .lineLimit(2)
                }
                StepStrip(steps: item.steps, style: .shaped, height: 10)
                    .padding(.top, Space.x1)
            }
            .padding(EdgeInsets(top: 9, leading: 12, bottom: 10, trailing: 12))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(WatchCardButtonStyle())
        .disabled(!isPro || workout.isCheckingAccess)
        .accessibilityLabel("Start \(item.name)")
        .accessibilityHint(Self.isFromPlan(item) ? "From your plan. \(item.detail)" : item.detail)
    }

    /// The small PLAN capsule, sized for a Watch row.
    private var planBadge: some View {
        Text("Plan")
            .watchFont(10, .bold)
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.lane)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.laneSoft, in: Capsule())
            .fixedSize()
    }

    // MARK: Week and friends

    /// This week's distance against the weekly goal iPhone set, in iPhone's unit.
    @ViewBuilder private func week(_ snapshot: WidgetSnapshot) -> some View {
        let unit = snapshot.unit
        let distance = snapshot.week(containing: .now).distance
        let done = distance / unit.metersPerUnit
        let goal = snapshot.weeklyGoal
        let goalText = goal.formatted(.number.precision(.fractionLength(0...1)))

        WatchOverline("This week", inset: 6)
            .padding(.top, 10)
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                Text(RunFormat.distance(distance, unit: unit, fractionDigits: 1))
                    .font(.watchMetric(20))
                    .foregroundStyle(.ink)
                Text(goal > 0 ? "of \(goalText) \(unit.distanceSymbol)" : unit.distanceSymbol)
                    .watchFont(13, digits: true)
                    .foregroundStyle(.inkMuted)
            }
            .lineLimit(1)
            if goal > 0 {
                TrackBar(progress: done / goal, tint: .lane, height: 6, track: .surfaceSunken)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 12, trailing: 12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .watchCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal > 0 ? "Weekly goal" : "This week")
        .accessibilityValue(goal > 0
            ? "\(RunFormat.distance(distance, unit: unit, fractionDigits: 1)) of \(goalText) \(WatchSpeech.unitName(unit, plural: true)), \(Int((min(done / goal, 1) * 100).rounded())) percent"
            : WatchSpeech.distance(distance, unit: unit))
    }

    /// Where the runner stands among friends this week; opens the leaderboard.
    @ViewBuilder private func friends(_ snapshot: WidgetSnapshot) -> some View {
        let leaderboard = snapshot.leaderboard()
        if let me = leaderboard.first(where: \.isMe), leaderboard.count > 1 {
            NavigationLink {
                WatchFriendsView(snapshot: snapshot)
            } label: {
                HStack(spacing: 10) {
                    IconBadge("person.2.fill", style: .lane, size: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Friends")
                            .watchFont(15, .semibold)
                            .foregroundStyle(.ink)
                        Text("You're #\(me.rank) this week")
                            .watchFont(12)
                            .foregroundStyle(.inkMuted)
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 12))
                .frame(minHeight: 52)
            }
            .buttonStyle(WatchCardButtonStyle())
            .accessibilityLabel("Friends, you're number \(me.rank) this week")
        }
    }
}
