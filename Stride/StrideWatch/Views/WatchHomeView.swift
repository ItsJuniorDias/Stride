import SwiftUI
import StrideKit
import StrideUI

/// Start list: a free run first, then distance and time goals, then interval workouts (Pro).
struct WatchHomeView: View {
    @Environment(WorkoutManager.self) private var workout
    /// The week and friends, from iPhone.
    @State private var snapshot = WidgetStore.load()
    /// Stride Pro as iPhone last reported it. Pro is bought and restored on iPhone only.
    @AppStorage(WatchContext.proActive) private var isPro = false
    /// The workouts iPhone sent; the interval presets until it has.
    @AppStorage(WatchContext.workouts) private var workoutsData = Data()
    @AppStorage(WatchVoice.enabledKey) private var speaksSteps = true

    private var library: [Workout] {
        WatchContext.decodeWorkouts(workoutsData) ?? IntervalPresets.all
    }

    private let goals: [(title: String, systemImage: String, goal: WorkoutManager.Goal)] = [
        ("5 km", "ruler", .init(type: .distance, distance: 5_000, name: "5 km")),
        ("10 km", "ruler", .init(type: .distance, distance: 10_000, name: "10 km")),
        ("Half marathon", "medal.fill", .init(type: .distance, distance: 21_097.5, name: "Half Marathon")),
        ("30 min", "stopwatch", .init(type: .time, duration: 1_800, name: "30 min")),
        ("60 min", "stopwatch", .init(type: .time, duration: 3_600, name: "60 min")),
    ]

    var body: some View {
        NavigationStack {
            List {
                // Access problems come first, where they're seen before a start button is tapped.
                if workout.isCheckingAccess {
                    ProgressView("Checking Health access…")
                }
                if let message = workout.authorizationError {
                    Label(message, systemImage: "heart.slash")
                        .font(.caption)
                        .foregroundStyle(.warning)
                }
                if workout.locationDenied {
                    Label("GPS off: no route or pace. Turn on Location for Stride in Settings.", systemImage: "location.slash")
                        .font(.caption)
                        .foregroundStyle(.warning)
                }

                Button {
                    Task { await workout.start(.init()) }
                } label: {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Image(systemName: "figure.run")
                            .font(.title2)
                            .foregroundStyle(.track)
                        Text("Free run")
                            .font(.headline)
                        Text("Outdoor")
                            .font(.caption)
                            .foregroundStyle(.inkMuted)
                    }
                    .padding(.vertical, Space.x2)
                }
                .disabled(workout.isCheckingAccess)

                if let snapshot, let me = snapshot.leaderboard().first(where: \.isMe), snapshot.leaderboard().count > 1 {
                    NavigationLink {
                        WatchFriendsView(snapshot: snapshot)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 0) {
                                Text("Friends")
                                Text("You're #\(me.rank) this week").font(.caption).foregroundStyle(.inkMuted)
                            }
                        } icon: {
                            Image(systemName: "person.2.fill").foregroundStyle(.lane)
                        }
                    }
                }

                Section("Goals") {
                    ForEach(goals, id: \.title) { item in
                        Button {
                            Task { await workout.start(item.goal) }
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                }
                .disabled(workout.isCheckingAccess)

                intervals
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

    /// Everyone sees the workouts; only Pro starts them. There's nothing to buy on the Watch.
    private var intervals: some View {
        Section {
            if !isPro {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Get Stride Pro on iPhone")
                        .font(.headline)
                    Text("Steps, haptics and voice cues on your wrist.")
                        .font(.caption)
                        .foregroundStyle(.inkMuted)
                }
                .padding(.vertical, Space.x1)
            }
            ForEach(library) { item in
                Button {
                    Task { await workout.start(.init(type: .intervals, name: item.name, workout: item)) }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .lineLimit(1)
                        if !item.detail.isEmpty {
                            Text(item.detail)
                                .font(.caption2)
                                .foregroundStyle(.inkMuted)
                                .lineLimit(2)
                        }
                    }
                }
                .disabled(!isPro || workout.isCheckingAccess)
            }
            if isPro {
                Toggle("Spoken steps", isOn: $speaksSteps)
            }
        } header: {
            HStack(spacing: Space.x1) {
                Text("Intervals")
                if !isPro { TagBadge("Pro") }
            }
        }
    }
}
