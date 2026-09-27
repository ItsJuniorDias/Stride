import SwiftUI
import SwiftData
import StrideKit
import StrideUI

// The Progress dashboard's challenges, friends and shoes sections, as they were before the redesign
// (the Progress screen keeps its earlier look). Their helpers are private copies: the Challenges,
// Friends and Shoes screens use their own, redesigned versions.

/// Progress: challenges still running, or a way to start one.
struct ChallengesSection: View {
    let samples: [RunSample]
    let now: Date
    @Query(sort: \Challenge.endDate) private var challenges: [Challenge]
    @State private var creating = false

    var body: some View {
        let running = challenges.filter { now < $0.endDate }.prefix(3)
        VStack(alignment: .leading, spacing: Space.x3) {
            SectionHeader(title: "Challenges", route: challenges.isEmpty ? nil : .challenges)
            ForEach(running) { challenge in
                NavigationLink(value: challenge) {
                    ProgressChallengeCard(challenge: challenge, status: challenge.status(samples: samples, now: now), now: now)
                }
                .buttonStyle(.plain)
            }
            if running.isEmpty {
                VStack(alignment: .leading, spacing: Space.x3) {
                    Illustration(name: "challengeMountain", contentMode: .fill)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    Label("Set yourself a challenge", systemImage: "flag.checkered")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ink)
                    Text("Run 100 km this month, climb a mountain's worth, or make your own.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                    Button("New challenge") { creating = true }
                        .buttonStyle(.strideSecondary)
                }
                .raisedCard()
            } else {
                Button {
                    creating = true
                } label: {
                    Label("New challenge", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Dimension.hitMin)
                }
            }
        }
        .sheet(isPresented: $creating) { NewChallengeView() }
    }
}

/// A challenge's progress, time left and whether the runner is on track.
private struct ProgressChallengeCard: View {
    let challenge: Challenge
    let status: ChallengeStatus
    let now: Date
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x3) {
                ProgressChallengeIcon(metric: challenge.metric, state: status.state)
                VStack(alignment: .leading, spacing: 2) {
                    Text(challenge.title).font(.headline).foregroundStyle(.ink)
                    Text(ProgressChallengeText.state(challenge, status: status, now: now))
                        .font(.caption)
                        .foregroundStyle(status.state == .completed ? Color.success : Color.inkMuted)
                }
                Spacer(minLength: 0)
            }
            ProgressBar(progress: status.fraction)
            HStack {
                Text(challenge.metric.progressText(value: status.value, target: status.target, unit: unit))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.ink)
                Spacer()
                if let pace = ProgressChallengeText.pace(challenge, status: status, unit: unit) {
                    Text(pace.text)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(pace.onTrack ? Color.success : Color.inkMuted)
                }
            }
        }
        .raisedCard()
        .accessibilityElement(children: .combine)
    }
}

private struct ProgressChallengeIcon: View {
    let metric: ChallengeMetric
    let state: ChallengeStatus.State

    var body: some View {
        Image(systemName: state == .completed ? "checkmark" : metric.symbol)
            .font(.body.weight(.semibold))
            .foregroundStyle(state == .completed ? Color.success : state == .missed ? Color.inkMuted : Color.lane)
            .frame(width: 40, height: 40)
            .background(state == .completed ? Color.success.opacity(0.15) : state == .missed ? Color.surfaceSunken : Color.laneSoft,
                        in: Circle())
            .accessibilityHidden(true)
    }
}

private enum ProgressChallengeText {
    /// "6 days left", "Last day", "Starts Oct 1", "Completed Sep 12", "Ended Sep 30".
    static func state(_ challenge: Challenge, status: ChallengeStatus, now: Date) -> String {
        let calendar = Calendar.current
        switch status.state {
        case .completed:
            return status.completedOn.map { "Completed \(shortDate($0))" } ?? "Completed"
        case .missed:
            return "Ended \(shortDate(challenge.endDate.addingTimeInterval(-1)))"
        case .upcoming:
            return "Starts \(shortDate(challenge.startDate))"
        case .active:
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: challenge.endDate).day ?? 0
            return days <= 1 ? "Last day" : "\(days) days left"
        }
    }

    /// "On track", or how far behind an even effort the runner is.
    static func pace(_ challenge: Challenge, status: ChallengeStatus, unit: UnitSystem) -> (text: String, onTrack: Bool)? {
        guard status.state == .active, let expected = status.expected else { return nil }
        guard let behind = challenge.metric.behind(value: status.value, expected: expected, unit: unit) else {
            return ("On track", true)
        }
        return (behind, false)
    }
}

/// Progress: this week against friends, or a way in.
struct FriendsSection: View {
    let samples: [RunSample]
    let now: Date
    @State private var friends = FriendsService.shared
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric

    var body: some View {
        let rows = Leaderboard.rows(me: friends.isSharing || !friends.friendCodes.isEmpty ? friends.myCard(from: samples, now: now) : nil,
                                    friends: friends.friendCards, period: .week, now: now)
        VStack(alignment: .leading, spacing: Space.x3) {
            SectionHeader(title: "Friends", route: .friends)
            if friends.friendCodes.isEmpty {
                NavigationLink(value: ProgressRoute.friends) {
                    VStack(alignment: .leading, spacing: Space.x3) {
                        Illustration(name: "emptyFriends", contentMode: .fill)
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        HStack(spacing: Space.x3) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Run with friends").font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                                Text("Swap codes, see each other's week and cheer each other on.")
                                    .font(.caption)
                                    .foregroundStyle(.inkMuted)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.inkMuted)
                        }
                    }
                    .raisedCard()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().padding(.leading, 64) }
                        ProgressLeaderboardRow(row: row, unit: unit, compact: true)
                    }
                }
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            }
        }
        .task(id: friends.friendCodes) { await friends.refresh() }
    }
}

/// A place, avatar, name and distance.
private struct ProgressLeaderboardRow: View {
    let row: LeaderboardRow
    let unit: UnitSystem
    var compact = false
    var cheer: (() -> Void)?
    var hasCheered = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Space.x3) {
            Text("\(row.rank)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(row.rank == 1 && row.distance > 0 ? Color.track : Color.inkMuted)
                .frame(minWidth: 20)
                .fixedSize()
            ProgressRunnerAvatar(initials: row.initials, code: row.code, isMe: row.isMe)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.x1) {
                    Text(row.isMe ? "You" : row.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    if row.cheeredMe {
                        Text("👏").font(.caption).accessibilityLabel("Cheered you")
                    }
                }
                detail.font(.caption).foregroundStyle(.inkMuted).lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
                    .accessibilityLabel("\(row.runs) runs\(row.streakWeeks > 1 ? ", \(row.streakWeeks)-week streak" : "")")
            }
            Spacer(minLength: Space.x2)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(RunFormat.distance(row.distance, unit: unit, fractionDigits: 1))
                    .font(.system(.headline, weight: .bold).width(.expanded))
                    .monospacedDigit()
                    .foregroundStyle(.ink)
                Text(unit.distanceSymbol).font(.caption2.weight(.semibold)).foregroundStyle(.inkMuted)
            }
            .fixedSize()
            if let cheer {
                Button(action: cheer) {
                    Image(systemName: hasCheered ? "hands.clap.fill" : "hands.clap")
                        .font(.body)
                        .foregroundStyle(hasCheered ? Color.track : Color.inkMuted)
                        .frame(width: 36, height: Dimension.hitMin)
                        .contentShape(Rectangle())
                }
                // Your own row keeps the space, so every distance lines up.
                .opacity(row.isMe ? 0 : 1)
                .disabled(row.isMe)
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: hasCheered) { _, new in new }
                .accessibilityLabel(hasCheered ? "Take back cheer for \(row.name)" : "Cheer \(row.name)")
            }
        }
        .padding(.horizontal, Space.x4)
        .padding(.vertical, compact ? Space.x2 : Space.x3)
        .frame(minHeight: Dimension.hitMin)
        .background(row.isMe ? Color.trackSoft.opacity(0.5) : Color.clear)
        .accessibilityElement(children: .contain)
    }

    private var detail: Text {
        let runs = Text("\(row.runs) \(row.runs == 1 ? "run" : "runs")")
        guard row.streakWeeks > 1 else { return runs }
        return runs + Text(" · \(Image(systemName: "flame.fill")) \(row.streakWeeks) wk")
    }
}

private struct ProgressRunnerAvatar: View {
    let initials: String
    let code: String
    var isMe = false
    var size: CGFloat = 36

    var body: some View {
        // A stable color per friend (hashValue changes every launch).
        let color = isMe ? Color.track : Shoe.colors[code.unicodeScalars.reduce(0) { $0 + Int($1.value) } % Shoe.colors.count]
        Text(initials)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Progress: the shoes in rotation and how worn they are.
struct ShoesSection: View {
    @Query(filter: #Predicate<Shoe> { !$0.isRetired }, sort: \Shoe.createdAt) private var shoes: [Shoe]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.defaultShoeID) private var defaultShoeRaw = ""
    @State private var adding = false

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            SectionHeader(title: "Shoes", route: .shoes)
            if shoes.isEmpty {
                VStack(alignment: .leading, spacing: Space.x3) {
                    if Illustration.exists("emptyShoes") {
                        Illustration(name: "emptyShoes", contentMode: .fill)
                            .frame(height: 140)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    Label("Track your shoes", systemImage: "shoe.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ink)
                    Text("See how far each pair has gone and when it's time for a new one.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                    Button("Add shoe") { adding = true }
                        .buttonStyle(.strideSecondary)
                }
                .raisedCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(shoes.prefix(3).enumerated()), id: \.element.id) { index, shoe in
                        if index > 0 { Divider().padding(.leading, 68) }
                        NavigationLink(value: shoe) {
                            ProgressShoeRow(shoe: shoe, unit: unit, isDefault: shoe.id.uuidString == defaultShoeRaw)
                                .padding(.horizontal, Space.x4)
                                .padding(.vertical, Space.x3)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            }
        }
        .sheet(isPresented: $adding) { ShoeEditorView(shoe: nil) }
    }
}

/// A shoe's icon in its color.
private struct ProgressShoeIcon: View {
    let shoe: Shoe
    var size: CGFloat = 40

    var body: some View {
        Image(systemName: "shoe.fill")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(shoe.isRetired ? Color.inkMuted : shoe.color)
            .frame(width: size, height: size)
            .background((shoe.isRetired ? Color.inkMuted : shoe.color).opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

/// Name, distance and wear.
private struct ProgressShoeRow: View {
    let shoe: Shoe
    let unit: UnitSystem
    let isDefault: Bool
    /// Off in lists, which draw their own disclosure indicator.
    var showsChevron = true

    var body: some View {
        HStack(spacing: Space.x3) {
            ProgressShoeIcon(shoe: shoe)
            VStack(alignment: .leading, spacing: Space.x1) {
                HStack(spacing: Space.x2) {
                    Text(shoe.displayName).font(.headline).foregroundStyle(.ink).lineLimit(1)
                    if isDefault {
                        Text("Default")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.lane)
                            .padding(.horizontal, Space.x2)
                            .padding(.vertical, 2)
                            .background(Color.laneSoft, in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                if !shoe.brand.isEmpty {
                    Text(shoe.brand).font(.caption).foregroundStyle(.inkMuted).lineLimit(1)
                }
                ProgressBar(progress: shoe.wear, tint: ProgressShoeWear.tint(shoe), height: 6)
                    .padding(.vertical, 2)
                HStack {
                    Text("\(ProgressShoeWear.distance(shoe.totalDistance, unit: unit)) of \(ProgressShoeWear.distance(shoe.maxDistance, unit: unit)) \(unit.distanceSymbol)")
                        .monospacedDigit()
                        .foregroundStyle(.inkMuted)
                    Spacer()
                    if shoe.isWornOut, !shoe.isRetired {
                        Text(shoe.wear >= 1 ? "Replace now" : "Replace soon").foregroundStyle(.warning)
                    }
                }
                .font(.caption.weight(.medium))
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.inkMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private enum ProgressShoeWear {
    /// Whole units: shoe distances are hundreds of kilometers.
    static func distance(_ meters: Double, unit: UnitSystem) -> String {
        Int((meters / unit.metersPerUnit).rounded()).formatted()
    }

    static func tint(_ shoe: Shoe) -> Color {
        if shoe.isRetired { return .inkMuted }
        if shoe.wear >= 1 { return .danger }
        if shoe.isWornOut { return .warning }
        return shoe.color
    }
}
