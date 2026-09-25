import SwiftUI
import StrideKit
import StrideUI

/// Start list: a free run first, then distance and time goals.
struct WatchHomeView: View {
    @Environment(WorkoutManager.self) private var workout
    /// The week and friends, from iPhone.
    @State private var snapshot = WidgetStore.load()

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
}
