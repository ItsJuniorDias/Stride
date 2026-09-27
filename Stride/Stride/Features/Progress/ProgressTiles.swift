import SwiftUI
import SwiftData
import StrideKit
import StrideUI

// The last row of Progress: challenges and shoes side by side, then friends this week.

/// A tile's title with the chevron that says it opens a screen.
private struct TileTitle: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(.ink)
            Spacer(minLength: Space.x1)
            DisclosureChevron()
        }
    }
}

/// A half-width raised tile that opens a Progress screen.
private struct ProgressTile<Content: View>: View {
    let title: String
    let route: ProgressRoute
    @ViewBuilder let content: Content

    var body: some View {
        NavigationLink(value: route) {
            VStack(alignment: .leading, spacing: 10) {
                TileTitle(title: title)
                content
            }
            .padding(Space.x4)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// Progress: the challenge running now (or next), how far along it is and the time left. Opens
/// every challenge.
struct ProgressChallengesTile: View {
    let samples: [RunSample]
    let now: Date
    @Query(sort: \Challenge.endDate) private var challenges: [Challenge]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        ProgressTile(title: "Challenges", route: .challenges) {
            if let challenge = featured {
                let status = challenge.status(samples: samples, now: now)
                HStack(spacing: 10) {
                    ArtThumbnail(name: "challengeMountain", width: 40, height: 40)
                    Text(challenge.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                TrackBar(progress: status.fraction, tint: status.state == .completed ? .success : .lane, height: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.metric.progressText(value: status.value, target: status.target, unit: unit))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.ink)
                    if let toGo = toGo(challenge, status: status) {
                        Text(toGo)
                    }
                    Text(timeLeft(challenge, status: status))
                        .foregroundStyle(status.state == .completed ? Color.success : Color.inkMuted)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            } else {
                ArtThumbnail(name: "challengeMountain", width: nil, height: 64)
                Text("Set yourself a goal, like 100 km this month.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The one running now that ends soonest, or else the next to start.
    private var featured: Challenge? {
        challenges.first { $0.startDate <= now && now < $0.endDate } ?? challenges.first { now < $0.endDate }
    }

    /// "27.6 km to go", while there's some left.
    private func toGo(_ challenge: Challenge, status: ChallengeStatus) -> String? {
        guard status.state == .active || status.state == .upcoming else { return nil }
        let left = max(status.target - status.value, 0)
        let shown = challenge.metric.shownValue(left, unit: unit)
        guard shown > 0 else { return nil }
        return "\(challenge.metric.number(left, unit: unit)) \(challenge.metric.displayUnit(unit, count: shown)) to go"
    }

    /// "5 days left", "Last day", "Starts Oct 1", "Completed".
    private func timeLeft(_ challenge: Challenge, status: ChallengeStatus) -> String {
        switch status.state {
        case .completed: return "Completed"
        case .missed: return "Ended"
        case .upcoming: return "Starts \(shortDate(challenge.startDate))"
        case .active:
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: challenge.endDate).day ?? 0
            return days <= 1 ? "Last day" : "\(days) days left"
        }
    }
}

/// Progress: the shoes in rotation, the default first, and how worn they are. Opens every shoe.
struct ProgressShoesTile: View {
    @Query(filter: #Predicate<Shoe> { !$0.isRetired }, sort: \Shoe.createdAt) private var shoes: [Shoe]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.defaultShoeID) private var defaultShoeRaw = ""

    var body: some View {
        ProgressTile(title: "Shoes", route: .shoes) {
            if shoes.isEmpty {
                ArtThumbnail(name: "emptyShoes", width: nil, height: 64)
                Text("See how far each pair has gone and when it's time for a new one.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                let ordered = shoes.filter { $0.id.uuidString == defaultShoeRaw } + shoes.filter { $0.id.uuidString != defaultShoeRaw }
                ForEach(ordered.prefix(2)) { shoe in
                    ShoeWearStack(shoe: shoe, unit: unit)
                }
            }
        }
    }
}

/// A shoe's name, a wear bar in its color (`warning` from 90% of its life, `danger` past it) and the
/// distance, stacked to fit half the width.
private struct ShoeWearStack: View {
    let shoe: Shoe
    let unit: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(shoe.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.ink)
                .lineLimit(1)
            TrackBar(progress: shoe.wear, tint: tint, height: 6)
            Text("\(whole(shoe.totalDistance)) of \(whole(shoe.maxDistance)) \(unit.distanceSymbol)")
                .font(.footnote.weight(.medium))
                .monospacedDigit()
                .foregroundStyle(.inkMuted)
                .lineLimit(1)
        }
    }

    private var tint: Color {
        if shoe.wear >= 1 { return .danger }
        if shoe.isWornOut { return .warning }
        return shoe.color
    }

    private func whole(_ meters: Double) -> String {
        Int((meters / unit.metersPerUnit).rounded()).formatted()
    }
}

/// Progress: this week against friends, ranked, with the runner's own row picked out; or a way in.
struct ProgressFriendsCard: View {
    let samples: [RunSample]
    let now: Date
    @State private var friends = FriendsService.shared
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        let me = friends.isSharing || !friends.friendCodes.isEmpty ? friends.myCard(from: samples, now: now) : nil
        let rows = Array(Leaderboard.rows(me: me, friends: friends.friendCards, period: .week, now: now).prefix(5))
        let longest = rows.map(\.distance).max() ?? 0
        VStack(alignment: .leading, spacing: Space.x1) {
            if friends.friendCodes.isEmpty {
                SectionHeading("Friends")
                    .padding(.bottom, Space.x2)
                NavigationLink(value: ProgressRoute.friends) {
                    HStack(spacing: Space.x3) {
                        ArtThumbnail(name: "emptyFriends", width: 64, height: 64)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Run with friends").font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                            Text("Swap codes, see each other's week and cheer each other on.")
                                .font(.footnote)
                                .foregroundStyle(.inkMuted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                        DisclosureChevron()
                    }
                    .padding(.bottom, Space.x2)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                SectionHeading("Friends", detail: "this week") {
                    SeeAllLink(route: .friends)
                }
                .padding(.bottom, Space.x1)
                ForEach(rows) { row in
                    FriendRankRow(row: row, longest: longest, unit: unit)
                }
            }
        }
        .padding(.top, Space.x4)
        .padding(.horizontal, Space.x4)
        .padding(.bottom, Space.x2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .task(id: friends.friendCodes) { await friends.refresh() }
    }
}

/// A place, avatar, name over a bar against the week's longest, and the distance.
private struct FriendRankRow: View {
    let row: LeaderboardRow
    let longest: Double
    let unit: UnitSystem

    var body: some View {
        let name = row.isMe ? "You" : row.name
        let distance = "\(RunFormat.distance(row.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
        HStack(spacing: Space.x3) {
            Text("\(row.rank)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.inkMuted)
                .frame(minWidth: 14, alignment: .leading)
                .fixedSize()
            RunnerAvatar(initials: row.initials, code: row.code, isMe: row.isMe, size: 32)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(name)
                    .font(.subheadline.weight(row.isMe ? .bold : .medium))
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                TrackBar(progress: longest > 0 ? row.distance / longest : 0, height: 4)
            }
            Text(distance)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.ink)
                .frame(minWidth: 64, alignment: .trailing)
                .fixedSize()
        }
        .frame(minHeight: Dimension.hitMin)
        .padding(.horizontal, Space.x2)
        .background(row.isMe ? Color.trackSoft.opacity(0.6) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, -Space.x2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Place \(row.rank), \(name)")
        .accessibilityValue("\(distance), \(row.runs) \(row.runs == 1 ? "run" : "runs")")
    }
}
