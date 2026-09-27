import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// A place on the Friends board: rank, avatar, name and distance over a bar scaled to the leader,
/// runs, streak and whether they cheered you, and the cheer button.
struct LeaderboardRowView: View {
    let row: LeaderboardRow
    let unit: UnitSystem
    /// The longest distance on the board, for the bar.
    let top: Double
    var period: LeaderboardPeriod = .week
    /// Nil hides the cheer column (the month, or while not sharing).
    var cheer: (() -> Void)?
    var hasCheered = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: Space.x3) {
            summary
            if let cheer {
                cheerButton(cheer)
            }
        }
        .padding(EdgeInsets(top: 10, leading: Space.x4, bottom: 10, trailing: cheer == nil ? Space.x4 : Space.x2))
        .frame(minHeight: Dimension.hitMin)
        .background(row.isMe ? Color.trackSoft.opacity(0.6) : Color.clear)
        .accessibilityElement(children: .contain)
    }

    private var distanceText: String {
        RunFormat.distance(row.distance, unit: unit, fractionDigits: 1)
    }

    private var showsStreak: Bool { period == .week && row.streakWeeks > 1 }
    private var showsCheeredMe: Bool { period == .week && row.cheeredMe }

    private var summary: some View {
        HStack(spacing: Space.x3) {
            Text("\(row.rank)")
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(row.rank == 1 && row.distance > 0 ? Color.ink : Color.inkMuted)
                .frame(minWidth: 14)
                .fixedSize()
            RunnerAvatar(initials: row.initials, code: row.code, isMe: row.isMe, size: 40)
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                    Text(row.isMe ? "You" : row.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ink)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 3 : 1)
                    Spacer(minLength: 0)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(distanceText)
                            .font(.system(size: 20, weight: .bold).width(.expanded))
                            .monospacedDigit()
                            .foregroundStyle(.ink)
                        Text(unit.distanceSymbol)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.inkMuted)
                    }
                    .fixedSize()
                }
                TrackBar(progress: top > 0 ? row.distance / top : 0, height: 6)
                    .padding(.top, 6)
                detail
                    .padding(.top, 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    /// "4 runs · 🔥 6 wk · Cheered you".
    private var detail: some View {
        HStack(spacing: Space.x1) {
            Text("\(row.runs) \(row.runs == 1 ? "run" : "runs")")
            if showsStreak {
                Text(verbatim: "·")
                Image(systemName: "flame")
                    .font(.caption2.weight(.semibold))
                Text("\(row.streakWeeks) wk")
            }
            if showsCheeredMe {
                Text(verbatim: "·")
                Text("Cheered you").foregroundStyle(.ink)
            }
        }
        .font(.footnote)
        .foregroundStyle(.inkMuted)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 2 : 1)
    }

    private var accessibilitySummary: String {
        var parts = ["\(row.rank). \(row.isMe ? "You" : row.name)", "\(distanceText) \(unit.distanceSymbol)",
                     "\(row.runs) \(row.runs == 1 ? "run" : "runs")"]
        if showsStreak { parts.append("\(row.streakWeeks)-week streak") }
        if showsCheeredMe { parts.append("cheered you") }
        return parts.joined(separator: ", ")
    }

    private func cheerButton(_ cheer: @escaping () -> Void) -> some View {
        Button(action: cheer) {
            Image(systemName: hasCheered ? "hands.clap.fill" : "hands.clap")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(hasCheered ? Color.track : Color.inkMuted)
                .frame(width: 36, height: 36)
                .background(hasCheered ? Color.trackSoft : Color.surfaceSunken, in: Circle())
                .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Your own row keeps the space, so every distance lines up.
        .opacity(row.isMe ? 0 : 1)
        .disabled(row.isMe)
        .accessibilityHidden(row.isMe)
        .sensoryFeedback(.success, trigger: hasCheered) { _, new in new }
        .accessibilityLabel(hasCheered ? "Take back cheer for \(row.name)" : "Cheer \(row.name)")
        .accessibilityAddTraits(hasCheered ? .isSelected : [])
    }
}

/// Initials in a soft circle: your own in the brand color, each friend in a stable color of their own.
struct RunnerAvatar: View {
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
            .background(isMe ? Color.trackSoft : color.opacity(0.16), in: Circle())
            .accessibilityHidden(true)
    }
}

/// The leaderboard, your code and invite, sharing settings and friends to manage.
struct FriendsView: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @State private var friends = FriendsService.shared
    @Environment(\.openURL) private var openURL
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.userName) private var userName = ""
    @State private var period: LeaderboardPeriod = .week
    @State private var adding = false
    @State private var confirmingRemoval: String?
    @State private var confirmingBlock: String?
    @State private var confirmingNewCode = false
    @State private var editingName = false
    @State private var nameDraft = ""

    var body: some View {
        let samples = runs.map(\.sample)
        let now = Date.now
        let me = friends.myCard(from: samples, now: now)
        let rows = Leaderboard.rows(me: me, friends: friends.friendCards, period: period, now: now)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                notices
                board(rows: rows, samples: samples, now: now)
                footnote
                    .padding(.top, Space.x2)
                    .padding(.horizontal, Space.x1)

                if !friends.silentFriends.isEmpty {
                    silentFriends
                        .padding(.top, Space.x5)
                }

                Button {
                    adding = true
                } label: {
                    Label("Add friend", systemImage: "person.badge.plus")
                }
                .buttonStyle(.stridePrimary)
                .disabled(accountMessage != nil)
                .padding(.top, Space.x5)

                codeAndSharing(samples: samples)
                    .padding(.top, Space.x5)
            }
            .padding(.horizontal, Space.x4)
            .padding(.top, Space.x3)
            .padding(.bottom, Space.x5)
        }
        .background(Color.surface)
        .navigationTitle("Friends")
        .navigationBarTitleDisplayMode(.large)
        .refreshable { await friends.refresh() }
        .task {
            friends.retryPendingDeletion()
            await friends.checkAccount()
            await friends.refresh()
        }
        // A new name goes out to friends (coalesced while typing).
        .onChange(of: userName) { friends.publish(from: samples) }
        .sheet(isPresented: $adding) { AddFriendView(initialCode: "") }
        .nameEditor(isPresented: $editingName, draft: $nameDraft) { userName = $0 }
        .confirmationDialog("Remove this friend?", isPresented: Binding(get: { confirmingRemoval != nil }, set: { if !$0 { confirmingRemoval = nil } }),
                            titleVisibility: .visible) {
            Button("Remove Friend", role: .destructive) {
                if let code = confirmingRemoval { friends.removeFriend(code) }
            }
        } message: {
            Text("You can add them again with their code.")
        }
        .confirmationDialog("Block this runner?", isPresented: Binding(get: { confirmingBlock != nil }, set: { if !$0 { confirmingBlock = nil } }),
                            titleVisibility: .visible) {
            Button("Block", role: .destructive) {
                if let code = confirmingBlock { friends.block(code) }
            }
            Button("Block and Change My Code", role: .destructive) {
                if let code = confirmingBlock {
                    friends.block(code)
                    friends.changeCode(samples: samples)
                }
            }
        } message: {
            Text("They're removed and can't be added again. To stop them seeing you too, change your code.")
        }
        .confirmationDialog("Change your code?", isPresented: $confirmingNewCode, titleVisibility: .visible) {
            Button("Change Code", role: .destructive) { friends.changeCode(samples: samples) }
        } message: {
            Text("Everyone who has your current code stops seeing you. Send the new one to the friends you want to keep.")
        }
    }

    private var accountMessage: String? {
        switch friends.account {
        case .noAccount, .restricted: "Sign in to iCloud in Settings to add friends and share your week."
        case .unavailable: "iCloud isn't available right now. Friends will update when it is."
        case .available, .unknown: nil
        }
    }

    /// iCloud trouble, the first-time explainer and news from the service, above the board.
    @ViewBuilder
    private var notices: some View {
        if let message = accountMessage {
            Label(message, systemImage: "icloud.slash")
                .font(.subheadline)
                .foregroundStyle(.warning)
                .raisedCard()
                .padding(.bottom, Space.x4)
        }
        if friends.friendCodes.isEmpty {
            IllustratedEmptyState(illustration: "emptyFriends", symbol: "person.2.fill", title: "Run with friends",
                                  message: "Add friends with their code, or send them yours. You'll see each other's week and can cheer each other on.",
                                  imageHeight: 200) {
                EmptyView()
            }
            .raisedCard(padding: 0)
            .padding(.bottom, Space.x4)
        }
        if let notice = friends.notice {
            Label(notice, systemImage: "info.circle")
                .font(.subheadline)
                .foregroundStyle(.ink)
                .raisedCard(fill: .laneSoft)
                .padding(.bottom, Space.x4)
        }
    }

    /// "This week · Sep 21 – 27" (weeks run Monday to Sunday for everyone), or "September".
    private func boardHeading(now: Date) -> (title: String, detail: String?) {
        switch period {
        case .week:
            var iso = Calendar(identifier: .iso8601)
            iso.timeZone = .current
            guard let week = iso.dateInterval(of: .weekOfYear, for: now) else { return ("This week", nil) }
            let last = max(week.end.addingTimeInterval(-1), week.start)
            return ("This week", (week.start..<last).formatted(.interval.month(.abbreviated).day()))
        case .month:
            return (now.formatted(.dateTime.month(.wide)), nil)
        }
    }

    private func board(rows: [LeaderboardRow], samples: [RunSample], now: Date) -> some View {
        let heading = boardHeading(now: now)
        let top = rows.map(\.distance).max() ?? 0
        // Cheers travel on my card: only while sharing, and only for this week.
        let canCheer = period == .week && friends.isSharing
        return VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeading(heading.title, detail: heading.detail, style: .overline) {
                PillPicker("Period", selection: $period, options: LeaderboardPeriod.allCases, size: .compact,
                           background: .surfaceSunken) { $0 == .week ? "Week" : "Month" }
            }
            .frame(minHeight: Dimension.hitMin)
            GroupedCard(dividerInset: 98) {
                ForEach(rows) { row in
                    LeaderboardRowView(row: row, unit: unit, top: top, period: period,
                                       cheer: canCheer ? { friends.toggleCheer(row.code, samples: samples) } : nil,
                                       hasCheered: friends.hasCheered(row.code))
                        .contentShape(.contextMenuPreview, Rectangle())
                        .contextMenu {
                            if !row.isMe { friendActions(code: row.code, name: row.name) }
                        }
                }
            }
        }
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(footnoteText)
            if let message = friends.errorMessage {
                Text(message).foregroundStyle(.warning)
            }
        }
        .font(.footnote)
        .foregroundStyle(.inkMuted)
    }

    private var footnoteText: String {
        let week = period == .week ? "Weeks run Monday to Sunday, the same for everyone. " : ""
        if friends.friendCodes.isEmpty {
            return week + "Add a friend with their code, or send them yours."
        } else if !friends.isSharing {
            return week + "Friends see you, and your cheers, only when sharing is on."
        } else {
            return week + "Touch and hold a friend to remove, block or report them."
        }
    }

    @ViewBuilder
    private func friendActions(code: String, name: String) -> some View {
        Button("Remove Friend", systemImage: "person.badge.minus") { confirmingRemoval = code }
        Button("Block", systemImage: "hand.raised", role: .destructive) { confirmingBlock = code }
        if let url = AppInfo.reportURL(name: name, code: code) {
            Button("Report Name", systemImage: "exclamationmark.bubble") { openURL(url) }
        }
    }

    /// Friends whose card couldn't be found (not sharing), so they can still be removed.
    private var silentFriends: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeading("Not sharing right now", style: .overline)
            GroupedCard {
                ForEach(friends.silentFriends, id: \.self) { code in
                    HStack {
                        Text(ShareCode.display(code))
                            .font(.subheadline.monospaced())
                            .foregroundStyle(.inkMuted)
                        Spacer()
                        Menu {
                            friendActions(code: code, name: ShareCode.display(code))
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.inkMuted)
                                .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Actions for \(ShareCode.display(code))")
                    }
                    .padding(.leading, Space.x4)
                    .padding(.trailing, Space.x1)
                    .frame(minHeight: 52)
                }
            }
        }
    }

    /// Your code with the invite, sharing on or off, and the name friends see.
    private func codeAndSharing(samples: [RunSample]) -> some View {
        GroupedCard {
            codeBlock
                .padding(Space.x4)
            SettingToggleRow("Share my running", subtitle: "Only with people who have your code",
                             isOn: Binding(get: { friends.isSharing }, set: { friends.setSharing($0, samples: samples) }))
                .disabled(accountMessage != nil && !friends.isSharing)
                .accessibilityHint("Turning it off removes your card")
            Button {
                nameDraft = userName
                editingName = true
            } label: {
                HStack(spacing: Space.x2) {
                    Text("Name friends see")
                        .foregroundStyle(.ink)
                    Spacer(minLength: Space.x2)
                    HStack(spacing: 6) {
                        Text(FriendsService.publicName(userName))
                            .lineLimit(1)
                        Image(systemName: "pencil")
                            .font(.subheadline.weight(.semibold))
                            .accessibilityHidden(true)
                    }
                    .foregroundStyle(.inkMuted)
                }
                .font(.body)
                .padding(.horizontal, Space.x4)
                .frame(minHeight: 48)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Name friends see")
            .accessibilityValue(FriendsService.publicName(userName))
            .accessibilityHint("Edits your name")
        }
    }

    @ViewBuilder
    private var codeBlock: some View {
        if friends.isSharing {
            let code = friends.myCode
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.x3) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your code").metricLabelStyle()
                        Text(ShareCode.display(code))
                            .font(.system(size: 28, weight: .bold).width(.expanded))
                            .monospacedDigit()
                            .tracking(0.5)
                            .foregroundStyle(.ink)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .speechSpellsOutCharacters()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ArtThumbnail(name: "emptyFriends", width: 56, height: 56)
                }
                Text("Friends with this code see your name, weekly and monthly distance, streak and last run.")
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .padding(.top, Space.x3)
                HStack(spacing: Space.x3) {
                    ShareLink(item: StrideLink.invite(code: code),
                              subject: Text("Run with me on Stride"),
                              message: Text("Add me on Stride with my code \(ShareCode.display(code)):")) {
                        OutlineCapsuleLabel(title: "Share invite", systemImage: "square.and.arrow.up", height: Dimension.hitMin,
                                            horizontalPadding: 18)
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 0)
                    LinkButton("Change my code") { confirmingNewCode = true }
                }
                .padding(.top, Space.x3)
            }
        } else {
            HStack(spacing: Space.x3) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your code").metricLabelStyle()
                    Text("Turn on sharing below to get your code and send it to friends.")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                ArtThumbnail(name: "emptyFriends", width: 56, height: 56)
            }
            .accessibilityElement(children: .combine)
        }
    }
}

/// Adds a friend by code, typed or from an invite link.
struct AddFriendView: View {
    let initialCode: String
    @Environment(\.dismiss) private var dismiss
    @State private var friends = FriendsService.shared
    @State private var code = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ABCD-EFGH", text: $code)
                        .font(.system(.title3, weight: .semibold).width(.expanded))
                        .monospaced()
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .focused($focused)
                        .onSubmit(add)
                } header: {
                    Text("Friend code")
                } footer: {
                    Text(errorMessage ?? "Ask your friend for the code under Progress › Friends in their Stride.")
                        .foregroundStyle(errorMessage == nil ? Color.inkMuted : Color.warning)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle("Add friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Add", action: add).disabled(ShareCode.normalize(code) == nil)
                    }
                }
            }
            .onAppear {
                code = initialCode.isEmpty ? "" : ShareCode.display(initialCode)
                focused = initialCode.isEmpty
            }
        }
        .presentationDetents([.medium])
    }

    private func add() {
        guard !isAdding else { return }
        isAdding = true
        errorMessage = nil
        Task {
            defer { isAdding = false }
            do {
                try await friends.addFriend(code)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}
