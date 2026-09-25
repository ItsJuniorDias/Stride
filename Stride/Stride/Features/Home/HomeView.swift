import SwiftUI
import SwiftData
import StrideKit
import StrideUI

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Environment(MirroredWorkout.self) private var mirrored
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.weeklyGoal) private var weeklyGoal = 20.0
    @AppStorage(StrideSettings.userName) private var userName = ""
    @Environment(\.scenePhase) private var scenePhase
    /// Mixed routes (runs and plans); a deleted run's screen shows its own "Run deleted" state.
    @State private var path = NavigationPath()
    /// Refreshed on foreground and at midnight, so the week, month and greeting don't go stale.
    @State private var now = Date.now

    private var thisWeek: [Run] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return runs.filter { week.contains($0.startDate) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x5) {
                    if runs.isEmpty {
                        welcomeCard
                    }
                    weeklyGoalCard

                    monthStrip

                    Button("Start a run") { selectedTab = .run }
                        .buttonStyle(.stridePrimary)

                    ActivePlanCard()

                    // Stride on Apple Watch is installed but hasn't recorded a run yet.
                    if mirrored.canStartOnWatch, !runs.contains(where: { $0.source == .watch }) {
                        watchCard
                    }

                    if let latest = runs.first {
                        VStack(alignment: .leading, spacing: Space.x3) {
                            Text("Latest run").font(.headline).foregroundStyle(.ink)
                            NavigationLink(value: latest) {
                                RunRow(run: latest, unit: unit)
                                    .padding(Space.x4)
                                    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(Space.x4)
            }
            .background(Color.surface)
            .navigationTitle(greeting)
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
            .planDestinations()
            .progressDestinations()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = .now }
        }
        // A run saved while the app stays open is newer than `now`; streaks would leave it out.
        .onChange(of: runs.count) { now = .now }
        .onChange(of: runs.first?.startDate) { now = .now }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
        }
    }

    private var watchCard: some View {
        HStack(spacing: Space.x3) {
            Illustration(name: "watchRun", contentMode: .fill)
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("Run with Apple Watch").font(.headline).foregroundStyle(.ink)
                Text("Open Stride on your watch, or tap Start on Watch in the Run tab. Heart rate and zones come along.")
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .raisedCard()
    }

    /// Before the first run: what Stride is about, and the way in.
    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Illustration(name: "onboardingWelcome", contentMode: .fill)
                .frame(height: 220)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
            Text("Your first run starts here").font(.title3.bold()).foregroundStyle(.ink)
            Text("Track every run with GPS on iPhone or Apple Watch, follow a plan, and watch your weeks add up.")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
        }
        .raisedCard()
    }

    private var weeklyGoalCard: some View {
        let km = thisWeek.reduce(0) { $0 + $1.distance } / unit.metersPerUnit
        let time = thisWeek.reduce(0) { $0 + $1.duration }
        let remaining = max(weeklyGoal - km, 0)
        return HStack(spacing: Space.x5) {
            ProgressRing(progress: weeklyGoal > 0 ? km / weeklyGoal : 0) {
                VStack(spacing: 2) {
                    Text(km.formatted(.number.precision(.fractionLength(1))))
                        .font(.metricSmall)
                        .monospacedDigit()
                        .foregroundStyle(.ink)
                    Text("of \(Int(weeklyGoal)) \(unit.distanceSymbol)").metricLabelStyle()
                }
            }
            .frame(width: 120, height: 120)

            VStack(alignment: .leading, spacing: Space.x1) {
                Text("This week").font(.headline).foregroundStyle(.ink)
                Text(thisWeek.isEmpty ? "No runs yet" : "\(thisWeek.count) \(thisWeek.count == 1 ? "run" : "runs") · \(RunFormat.duration(time))")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                Text(remaining > 0 ? "\(remaining.formatted(.number.precision(.fractionLength(1)))) \(unit.distanceSymbol) to go" : "Goal reached")
                    .font(.subheadline)
                    .foregroundStyle(remaining > 0 ? Color.inkMuted : Color.success)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.x4)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private var monthStrip: some View {
        let month = Calendar.current.dateInterval(of: .month, for: now)
        let monthRuns = runs.filter { month?.contains($0.startDate) ?? false }
        let distance = monthRuns.reduce(0) { $0 + $1.distance }
        let streak = Streaks.summary(of: runs.map(\.startDate), now: now).currentWeeks
        return HStack(spacing: Space.x3) {
            stripTile(MetricView("This month", value: RunFormat.distance(distance, unit: unit, fractionDigits: 1), unit: unit.distanceSymbol, size: .small))
            stripTile(MetricView("Runs", value: "\(monthRuns.count)", size: .small))
            stripTile(MetricView("Streak", value: "\(streak)", unit: streak == 1 ? "week" : "weeks", size: .small))
        }
        // Equal heights: every tile stretches to the tallest one.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func stripTile(_ metric: MetricView) -> some View {
        metric
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .padding(Space.x3)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    /// A large title fits about 18 characters on the smallest iPhones, so "Good afternoon, Alexandre"
    /// becomes "Hi, Alexandre", and a name too long even for that leaves just the time of day.
    private var greeting: String {
        let base = switch Calendar.current.component(.hour, from: now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        guard let name = userName.split(separator: " ").first.map(String.init) else { return base }
        let maxLength = 18
        let full = "\(base), \(name)"
        if full.count <= maxLength { return full }
        let short = "Hi, \(name)"
        return short.count <= maxLength ? short : base
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .environment(RunTracker())
        .environment(MirroredWorkout.shared)
        .modelContainer(for: [Run.self, Shoe.self, Challenge.self], inMemory: true)
}
