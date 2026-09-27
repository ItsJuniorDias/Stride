import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// The week against the goal, the way into a run, the month so far, the plan's next session, the
/// latest run and friends' weeks. Before the first run: what Stride does and where to start.
struct HomeView: View {
    @Binding var selectedTab: AppTab
    @Environment(MirroredWorkout.self) private var mirrored
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.weeklyGoal) private var weeklyGoal = 20.0
    @AppStorage(StrideSettings.userName) private var userName = ""
    @Environment(\.scenePhase) private var scenePhase
    @State private var friends = FriendsService.shared
    /// Mixed routes (runs and plans); a deleted run's screen shows its own "Run deleted" state.
    @State private var path = NavigationPath()
    /// Refreshed on foreground and at midnight, so the week, month and greeting don't go stale.
    @State private var now = Date.now

    private var thisWeek: [Run] {
        guard let week = Calendar.current.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return runs.filter { week.contains($0.startDate) }
    }

    /// Stride on Apple Watch is installed but hasn't recorded a run yet.
    private var suggestsWatch: Bool {
        mirrored.canStartOnWatch && !runs.contains { $0.source == .watch }
    }

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The date over the title in the design; under the native large title here.
                    Text(now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                        .metricLabelStyle()

                    if runs.isEmpty {
                        firstRun
                    } else {
                        overview
                    }
                }
                .padding(.horizontal, Space.x4)
                .padding(.bottom, Space.x5)
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

    // MARK: - Before the first run

    @ViewBuilder private var firstRun: some View {
        welcomeCard
            .padding(.top, Space.x3)
        ActivePlanCard()
            .padding(.top, Space.x4)
        if suggestsWatch {
            watchRow
                .padding(.top, Space.x3)
        }
    }

    /// What Stride is about, the weekly goal, and the way in.
    private var welcomeCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ArtThumbnail(name: "onboardingWelcome", width: nil, height: 168)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("Your first run starts here")
                    .font(.title2.bold())
                    .foregroundStyle(.ink)
                Text("Track runs with GPS on iPhone or Apple Watch, follow a plan, and see your weeks add up.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: Space.x2) {
                    Image(systemName: "target")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.lane)
                        .accessibilityHidden(true)
                    Text("Weekly goal \(Text(goalText).fontWeight(.semibold).foregroundStyle(.ink)) · no runs yet this week")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.inkMuted)
                }
                .padding(.top, 10)
            }
            .padding(.horizontal, Space.x1)
            .padding(.top, 14)

            Button { selectedTab = .run } label: {
                Label("Start a run", systemImage: "figure.run")
            }
            .buttonStyle(.stridePrimary)
            .padding(.top, Space.x4)
        }
        .raisedCard(padding: Space.x3)
    }

    /// Open Stride on Apple Watch; the Run tab can start it there too.
    private var watchRow: some View {
        Button { selectedTab = .run } label: {
            HStack(spacing: 14) {
                ArtThumbnail(name: "watchRun")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run with Apple Watch")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.ink)
                    Text("Open Stride on your watch to start. Heart rate and zones come along.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DisclosureChevron()
            }
            .raisedCard(padding: Space.x3)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens the Run tab")
    }

    // MARK: - With runs

    @ViewBuilder private var overview: some View {
        weekCard
            .padding(.top, Space.x3)

        Button { selectedTab = .run } label: {
            Label("Start a run", systemImage: "figure.run")
        }
        .buttonStyle(.stridePrimary)
        .padding(.top, Space.x4)

        monthStrip
            .padding(.top, 20)

        ActivePlanCard()
            .padding(.top, 14)

        if suggestsWatch {
            watchRow
                .padding(.top, Space.x3)
        }

        if let latest = runs.first {
            VStack(alignment: .leading, spacing: Space.x1) {
                SectionHeading("Latest run") {
                    LinkButton("All runs") { selectedTab = .activities }
                }
                NavigationLink(value: latest) {
                    RunRow(run: latest, unit: unit, showsChevron: true, marksStart: true)
                        .raisedCard(padding: Space.x3)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 14)
        }

        friendsSection
            .padding(.top, 14)
    }

    /// The ring against the weekly goal, what's left, and a bar per day.
    private var weekCard: some View {
        let distance = thisWeek.reduce(0) { $0 + $1.distance } / unit.metersPerUnit
        let time = thisWeek.reduce(0) { $0 + $1.duration }
        let remaining = max(weeklyGoal - distance, 0)
        let reached = weeklyGoal > 0 && remaining == 0
        return HStack(spacing: 20) {
            WeekRing(progress: weeklyGoal > 0 ? distance / weeklyGoal : 0, tint: reached ? .success : .lane) {
                VStack(spacing: 2) {
                    Text(distance.formatted(.number.precision(.fractionLength(1))))
                        .font(.metricMedium)
                        .monospacedDigit()
                        .foregroundStyle(.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text("of \(goalText)")
                        .font(.metricLabel)
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(.inkMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .padding(.horizontal, Space.x3)
            }
            .frame(width: 112, height: 112)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Weekly goal")
            .accessibilityValue("\(CoachScript.spokenDistance(distance * unit.metersPerUnit, unit: unit)) of \(goalText)")

            VStack(alignment: .leading, spacing: 2) {
                Text("This week").metricLabelStyle()
                Text(reached ? "Goal reached" : "\(remaining.formatted(.number.precision(.fractionLength(1)))) \(unit.distanceSymbol) to go")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(reached ? Color.success : Color.ink)
                    .padding(.top, 2)
                Text(thisWeek.isEmpty ? "No runs yet" : "\(thisWeek.count) \(thisWeek.count == 1 ? "run" : "runs") · \(RunFormat.duration(time))")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.inkMuted)
                WeekBars(days: WeekBars.Day.week(of: thisWeek, around: now, unit: unit))
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .raisedCard()
    }

    /// The month's distance, its runs, and the weekly streak.
    private var monthStrip: some View {
        let month = Calendar.current.dateInterval(of: .month, for: now)
        let monthRuns = runs.filter { month?.contains($0.startDate) ?? false }
        let distance = monthRuns.reduce(0) { $0 + $1.distance }
        let streak = Streaks.summary(of: runs.map(\.startDate), now: now).currentWeeks
        return HStack(spacing: Space.x3) {
            stripTile(StatTile(now.formatted(.dateTime.month(.wide)),
                               value: RunFormat.distance(distance, unit: unit, fractionDigits: 1), unit: unit.distanceSymbol))
            stripTile(StatTile("Runs", value: "\(monthRuns.count)"))
            stripTile(StatTile("Streak", value: "\(streak)", unit: streak == 1 ? "week" : "weeks"))
        }
        // Equal heights: every tile stretches to the tallest one.
        .fixedSize(horizontal: false, vertical: true)
    }

    private func stripTile(_ tile: some View) -> some View {
        tile
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    // MARK: - Friends

    /// This week's leaderboard, top four (with you in it), once the runner has friends.
    @ViewBuilder private var friendsSection: some View {
        if !friends.friendCodes.isEmpty {
            let rows = leaderboard
            if !rows.isEmpty {
                VStack(alignment: .leading, spacing: Space.x1) {
                    SectionHeading("Friends this week") {
                        NavigationLink(value: ProgressRoute.friends) {
                            LinkLabel("Leaderboard")
                        }
                        .buttonStyle(.strideLink)
                    }
                    VStack(spacing: 6) {
                        let longest = max(rows.map(\.distance).max() ?? 0, 1)
                        ForEach(rows) { row in
                            FriendWeekRow(row: row, fraction: row.distance / longest, unit: unit)
                        }
                    }
                    .padding(.vertical, Space.x3)
                    .padding(.horizontal, Space.x4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                }
            }
        }
    }

    private var leaderboard: [LeaderboardRow] {
        let me = friends.myCard(from: runs.map(\.sample), now: now)
        let rows = Leaderboard.rows(me: me, friends: friends.friendCards, period: .week, now: now)
        var shown = Array(rows.prefix(4))
        if shown.count == 4, !shown.contains(where: \.isMe), let mine = rows.first(where: \.isMe) {
            shown[3] = mine
        }
        return shown
    }

    // MARK: - Words

    /// "30 km", the goal in the runner's unit.
    private var goalText: String {
        "\(weeklyGoal.formatted(.number.precision(.fractionLength(0...1)))) \(unit.distanceSymbol)"
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

/// The weekly goal as a 12pt ring on a sunken track, in the data color (`success` once reached).
private struct WeekRing<Center: View>: View {
    let progress: Double
    let tint: Color
    @ViewBuilder let center: Center

    var body: some View {
        ZStack {
            Circle().stroke(Color.surfaceSunken, lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            center
        }
        .padding(6)
        .animation(.snappy, value: progress)
    }
}

/// A place on this week's leaderboard: rank, avatar, name, a bar against the leader, distance.
private struct FriendWeekRow: View {
    let row: LeaderboardRow
    let fraction: Double
    let unit: UnitSystem

    var body: some View {
        let distance = "\(RunFormat.distance(row.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
        HStack(spacing: 10) {
            Text(verbatim: "\(row.rank)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.inkMuted)
                .frame(width: 14, alignment: .leading)
            RunnerAvatar(initials: row.initials, code: row.code, isMe: row.isMe, size: 28)
            Text(row.isMe ? "You" : row.name)
                .font(.subheadline.weight(row.isMe ? .semibold : .regular))
                .foregroundStyle(.ink)
                .lineLimit(1)
                .frame(width: 104, alignment: .leading)
            TrackBar(progress: fraction, height: 6)
            Text(distance)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 62, alignment: .trailing)
        }
        .frame(minHeight: 28)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.rank), \(row.isMe ? "You" : row.name)")
        .accessibilityValue(CoachScript.spokenDistance(row.distance, unit: unit))
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .environment(RunTracker())
        .environment(MirroredWorkout.shared)
        .modelContainer(for: [Run.self, Shoe.self, Challenge.self], inMemory: true)
}
