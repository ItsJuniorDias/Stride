import SwiftUI
import StrideKit
import StrideUI

/// Start list: a free run first, then distance and time goals.
struct WatchHomeView: View {
    @Environment(WorkoutManager.self) private var workout

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
                Button {
                    workout.start(.init())
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

                Section("Goals") {
                    ForEach(goals, id: \.title) { item in
                        Button {
                            workout.start(item.goal)
                        } label: {
                            Label(item.title, systemImage: item.systemImage)
                        }
                    }
                }

                if let message = workout.authorizationError {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.warning)
                }
                if workout.locationDenied {
                    Label("GPS off: no route or pace. Turn on Location for Stride in Settings.", systemImage: "location.slash")
                        .font(.caption)
                        .foregroundStyle(.warning)
                }
            }
            .navigationTitle("Stride")
        }
        .task { await workout.requestAuthorization() }
    }
}
