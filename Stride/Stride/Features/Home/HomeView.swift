import SwiftUI
import SwiftData
import StrideKit
import StrideUI

struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.weeklyGoal) private var weeklyGoal = 20.0
    @AppStorage(StrideSettings.userName) private var userName = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Run] = []
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
                    weeklyGoalCard

                    monthStrip

                    Button("Start a run") { selectedTab = .run }
                        .buttonStyle(.stridePrimary)

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
        }
        .onChange(of: runs) { path.removeAll { $0.isDeleted || $0.modelContext == nil } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = .now }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.significantTimeChangeNotification)) { _ in
            now = .now
        }
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
        let streak = weekStreak
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

    /// Consecutive weeks with at least one run, counting back from this week
    /// (or from last week, if there's no run yet this week).
    private var weekStreak: Int {
        let calendar = Calendar.current
        let weeks = Set(runs.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0.startDate)?.start })
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !weeks.contains(cursor) {
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        var count = 0
        while weeks.contains(cursor) {
            count += 1
            cursor = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) ?? cursor
        }
        return count
    }

    private var greeting: String {
        let name = userName.split(separator: " ").first.map(String.init)
        let base = switch Calendar.current.component(.hour, from: now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
        return name.map { "\(base), \($0)" } ?? base
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(for: [Run.self, Shoe.self], inMemory: true)
}
