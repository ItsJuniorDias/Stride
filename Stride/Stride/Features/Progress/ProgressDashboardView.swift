import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Totals by week, month and year, training load, streaks, race predictions, personal records,
/// challenges and shoes.
struct ProgressDashboardView: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @Environment(\.scenePhase) private var scenePhase
    @State private var path = NavigationPath()
    /// Refreshed on foreground and at midnight, so "this week" and streaks don't go stale.
    @State private var now = Date.now

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                let samples = runs.map(\.sample)
                // Decoded once per change here, not in every section's body.
                let entries = runs.map(\.recordEntry)
                let records = PersonalRecords.best(of: entries)
                VStack(alignment: .leading, spacing: Space.x5) {
                    PeriodStatsCard(samples: samples, firstRun: runs.last?.startDate, now: now)
                    TrainingLoadCard(samples: samples, now: now)
                    StreaksCard(samples: samples, now: now)
                    FriendsSection(samples: samples, now: now)
                    RacePredictorCard(entries: entries, now: now)
                    RecordsSection(records: records, runs: runs)
                    ChallengesSection(samples: samples, now: now)
                    ShoesSection()
                }
                .padding(Space.x4)
            }
            .background(Color.surface)
            .navigationTitle("Progress")
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
            .progressDestinations()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = .now }
        }
        // A run saved while the app stays open is newer than `now`; streaks and challenges would leave it out.
        .onChange(of: runs.count) { now = .now }
        .onChange(of: runs.first?.startDate) { now = .now }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
        }
    }
}

#Preview {
    ProgressDashboardView()
        .modelContainer(for: [Run.self, Shoe.self, Challenge.self], inMemory: true)
}
