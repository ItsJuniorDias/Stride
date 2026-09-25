import SwiftUI
import SwiftData
import StrideKit
import StrideUI

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
                    HStack(spacing: Space.x3) {
                        Image(systemName: "person.2.fill")
                            .font(.title3)
                            .foregroundStyle(.lane)
                            .frame(width: 44, height: 44)
                            .background(Color.laneSoft, in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Run with friends").font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                            Text("Swap codes, see each other's week and cheer each other on.")
                                .font(.caption)
                                .foregroundStyle(.inkMuted)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.inkMuted)
                    }
                    .raisedCard()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.prefix(5).enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Divider().padding(.leading, 64) }
                        LeaderboardRowView(row: row, unit: unit, compact: true)
                    }
                }
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            }
        }
        .task(id: friends.friendCodes) { await friends.refresh() }
    }
}

/// A place, avatar, name and distance.
struct LeaderboardRowView: View {
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
            RunnerAvatar(initials: row.initials, code: row.code, isMe: row.isMe)
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
            .background(color.opacity(0.16), in: Circle())
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

    var body: some View {
        let samples = runs.map(\.sample)
        let me = friends.myCard(from: samples)
        let rows = Leaderboard.rows(me: me, friends: friends.friendCards, period: period)
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                if let message = accountMessage {
                    Label(message, systemImage: "icloud.slash")
                        .font(.subheadline)
                        .foregroundStyle(.warning)
                        .raisedCard()
                }
                if let notice = friends.notice {
                    Label(notice, systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.ink)
                        .raisedCard(fill: .laneSoft)
                }

                VStack(alignment: .leading, spacing: Space.x3) {
                    Picker("Period", selection: $period) {
                        ForEach(LeaderboardPeriod.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    VStack(spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { Divider().padding(.leading, 64) }
                            // Cheers travel on my card: only while sharing.
                            LeaderboardRowView(row: row, unit: unit,
                                               cheer: period == .week && friends.isSharing ? { friends.toggleCheer(row.code, samples: samples) } : nil,
                                               hasCheered: friends.hasCheered(row.code))
                                .contextMenu {
                                    if !row.isMe { friendActions(code: row.code, name: row.name) }
                                }
                        }
                    }
                    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                    VStack(alignment: .leading, spacing: Space.x1) {
                        if period == .week {
                            Text("Weeks run Monday to Sunday, the same for everyone.")
                        }
                        if friends.friendCodes.isEmpty {
                            Text("Add a friend with their code, or send them yours.")
                        } else if !friends.isSharing {
                            Text("Friends see you, and your cheers, only when sharing is on.")
                        } else {
                            Text("Touch and hold a friend to remove, block or report them.")
                        }
                        if let message = friends.errorMessage {
                            Text(message).foregroundStyle(.warning)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
                }

                if !friends.silentFriends.isEmpty {
                    silentFriends
                }

                Button {
                    adding = true
                } label: {
                    Label("Add friend", systemImage: "person.badge.plus")
                }
                .buttonStyle(.stridePrimary)
                .disabled(accountMessage != nil)

                shareCard(samples: samples)
                sharingSettings(samples: samples)
            }
            .padding(Space.x4)
        }
        .background(Color.surface)
        .navigationTitle("Friends")
        .refreshable { await friends.refresh() }
        .task {
            friends.retryPendingDeletion()
            await friends.checkAccount()
            await friends.refresh()
        }
        // A new name goes out to friends (coalesced while typing).
        .onChange(of: userName) { friends.publish(from: samples) }
        .sheet(isPresented: $adding) { AddFriendView(initialCode: "") }
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
        VStack(alignment: .leading, spacing: Space.x3) {
            Text("Not sharing right now").font(.headline).foregroundStyle(.ink)
            VStack(spacing: 0) {
                ForEach(Array(friends.silentFriends.enumerated()), id: \.element) { index, code in
                    if index > 0 { Divider().padding(.leading, Space.x4) }
                    HStack {
                        Text(ShareCode.display(code)).font(.subheadline.monospaced()).foregroundStyle(.inkMuted)
                        Spacer()
                        Menu {
                            friendActions(code: code, name: ShareCode.display(code))
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                        }
                        .accessibilityLabel("Actions for \(ShareCode.display(code))")
                    }
                    .padding(.leading, Space.x4)
                }
            }
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        }
    }

    @ViewBuilder
    private func shareCard(samples: [RunSample]) -> some View {
        if friends.isSharing {
            let code = friends.myCode
            VStack(alignment: .leading, spacing: Space.x3) {
                Text("Your code").metricLabelStyle()
                HStack {
                    Text(ShareCode.display(code))
                        .font(.system(.title, weight: .bold).width(.expanded))
                        .monospaced()
                        .foregroundStyle(.ink)
                        .textSelection(.enabled)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Spacer()
                    ShareLink(item: StrideLink.invite(code: code),
                              subject: Text("Run with me on Stride"),
                              message: Text("Add me on Stride with my code \(ShareCode.display(code)):")) {
                        Label("Invite", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                Text("Friends who add this code see your name, this week's and month's distance, your streak and your last run.")
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
                Button("Change my code") { confirmingNewCode = true }
                    .font(.subheadline.weight(.semibold))
            }
            .raisedCard()
        } else {
            VStack(alignment: .leading, spacing: Space.x2) {
                Label("Your code", systemImage: "qrcode").font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                Text("Turn on sharing below to get your code and send it to friends.")
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
            }
            .raisedCard()
        }
    }

    private func sharingSettings(samples: [RunSample]) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Toggle(isOn: Binding(get: { friends.isSharing }, set: { friends.setSharing($0, samples: samples) })) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Share my running").font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                    Text("Only with people who have your code. Turning it off removes your card.")
                        .font(.caption)
                        .foregroundStyle(.inkMuted)
                }
            }
            .tint(.track)
            .disabled(accountMessage != nil && !friends.isSharing)
            Divider()
            LabeledContent("Name friends see") {
                TextField("Your name", text: $userName)
                    .multilineTextAlignment(.trailing)
                    .textContentType(.givenName)
            }
            .font(.subheadline)
        }
        .raisedCard()
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
