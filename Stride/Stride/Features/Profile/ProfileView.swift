import SwiftUI
import SwiftData
import StoreKit
import StrideKit
import StrideUI

struct ProfileView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @State private var confirmingDeleteAll = false
    @AppStorage(StrideSettings.userName) private var userName = ""
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.weeklyGoal) private var weeklyGoal = 20.0
    @AppStorage(StrideSettings.yearlyGoal) private var yearlyGoal = 1_000.0
    @AppStorage(StrideSettings.autoPause) private var autoPause = true
    @AppStorage(StrideSettings.weightKg) private var weightKg = 70.0
    @AppStorage(StrideSettings.maxHeartRate) private var maxHeartRate = HeartRateZone.defaultMaxHeartRate
    @AppStorage(StrideSettings.voiceCoach) private var voiceCoach = true
    @AppStorage(StrideSettings.voiceInterval) private var voiceInterval = 1.0
    @AppStorage(StrideSettings.voiceIncludePace) private var voiceIncludePace = true
    @AppStorage(StrideSettings.voiceIncludeTime) private var voiceIncludeTime = true
    @Environment(RunTracker.self) private var tracker
    @AppStorage(StrideSettings.healthSave) private var healthSave = false
    @State private var healthMessage: String?
    @State private var bodyMessage: String?
    @State private var healthDenied = false
    @State private var upsell: ProFeature?
    @State private var managingSubscription = false
    @State private var restoreMessage: String?
    @State private var isRestoring = false
    @State private var editingName = false
    @State private var nameDraft = ""
    private var pro: ProStore { .shared }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x5) {
                    header
                        .padding(.bottom, -Space.x2)
                    proSection
                    goalsSection
                    trainingSection
                    voiceCoachSection
                    healthSection
                    runningSection
                    #if DEBUG
                    developerSection
                    #endif
                    dataSection
                }
                .padding(.horizontal, Space.x4)
                .padding(.top, Space.x2)
                .padding(.bottom, Space.x5)
            }
            .background(Color.surface)
            // The header carries the name as the screen's title; "Profile" names the back button.
            .navigationTitle("Profile")
            .toolbarVisibility(.hidden, for: .navigationBar)
            .navigationDestination(for: Run.self) { RunDetailView(run: $0) }
            .planDestinations()
            .progressDestinations()
            .onAppear { healthDenied = healthSave && HealthSync.shared.wasDenied }
            .task { await FriendsService.shared.checkAccount() }
            .onChange(of: unit) { WatchSync.shared.pushSettings() }
            .onChange(of: maxHeartRate) { WatchSync.shared.pushSettings() }
            .proPaywall($upsell)
            .manageSubscriptionsSheet(isPresented: $managingSubscription, subscriptionGroupID: pro.groupID ?? "")
            // Manage subscription may have changed the plan or turned renewal off.
            .onChange(of: managingSubscription) { _, isOpen in
                if !isOpen { Task { await pro.refresh() } }
            }
            .nameEditor(isPresented: $editingName, draft: $nameDraft) { name in
                userName = name
                // Friends see the new name (coalesced; only while sharing).
                FriendsService.shared.publish(from: runs.map(\.sample))
            }
            .confirmationDialog("Delete all runs, shoes and challenges?", isPresented: $confirmingDeleteAll, titleVisibility: .visible) {
                Button("Delete All", role: .destructive, action: deleteAll)
            } message: {
                Text("This can't be undone. Runs already saved to Apple Health stay there.")
            }
        }
    }
}

// MARK: - Header and Stride Pro

extension ProfileView {
    private var header: some View {
        HStack(spacing: 14) {
            avatar
            VStack(alignment: .leading, spacing: 0) {
                Text(userName.isEmpty ? "Profile" : userName)
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                Text(headerSubtitle)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            RoundIconButton("pencil", accessibilityLabel: userName.isEmpty ? "Add the name friends see" : "Edit the name friends see") {
                nameDraft = userName
                editingName = true
            }
        }
    }

    private var avatar: some View {
        Group {
            if let initial = userName.trimmingCharacters(in: .whitespaces).first {
                Text(String(initial).uppercased())
                    .font(.system(size: 26, weight: .heavy).width(.expanded))
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: 26, weight: .semibold))
            }
        }
        .foregroundStyle(.track)
        .frame(width: 64, height: 64)
        .background(Color.trackSoft, in: Circle())
        .accessibilityHidden(true)
    }

    /// "5-week streak · 812 km this year".
    private var headerSubtitle: String {
        let now = Date.now
        let streak = Streaks.summary(of: runs.map(\.startDate), now: now).currentWeeks
        let year = Calendar.current.dateInterval(of: .year, for: now)
        let yearDistance = runs.filter { year?.contains($0.startDate) ?? false }.reduce(0) { $0 + $1.distance } / unit.metersPerUnit
        var parts: [String] = []
        if streak > 0 { parts.append("\(streak)-week streak") }
        if yearDistance >= 1 { parts.append("\(Int(yearDistance).formatted()) \(unit.distanceSymbol) this year") }
        if parts.isEmpty { return runs.isEmpty ? "No runs yet" : "No runs yet this year" }
        return parts.joined(separator: " · ")
    }

    private var proSection: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            if pro.isPro {
                proCard
            } else {
                Button { upsell = .general } label: { proCard }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens Stride Pro")
                LinkButton(isRestoring ? "Restoring…" : "Restore purchases") {
                    isRestoring = true
                    Task {
                        restoreMessage = await pro.restore()
                        isRestoring = false
                    }
                }
                .disabled(isRestoring)
                .padding(.leading, Space.x1)
            }
            if let restoreMessage {
                Text(restoreMessage)
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .padding(.horizontal, Space.x1)
            }
        }
    }

    private var proCard: some View {
        let summary = pro.summary
        return HStack(spacing: Space.x3) {
            IconBadge("bolt.fill", style: .brand, size: 36, corner: .rounded)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Space.x2) {
                    Text("Stride Pro")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.ink)
                    if let chip = summary.chip {
                        SoftBadge(chip.title, tone: .neutral, dot: chip.isWarning ? .warning : .success)
                    }
                }
                Text(summary.detail)
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            if pro.isPro {
                if summary.canManage, pro.groupID != nil {
                    Button { managingSubscription = true } label: {
                        OutlineCapsuleLabel(title: "Manage")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Manage subscription")
                }
            } else {
                OutlineCapsuleLabel(title: "Upgrade")
                    .accessibilityHidden(true)
            }
        }
        .padding(EdgeInsets(top: 14, leading: Space.x4, bottom: 14, trailing: Space.x3))
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .contentShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - Goals and training

extension ProfileView {
    private var goalsSection: some View {
        let now = Date.now
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: now)
        let year = Calendar.current.dateInterval(of: .year, for: now)
        let weekDone = runs.filter { week?.contains($0.startDate) ?? false }.reduce(0) { $0 + $1.distance } / unit.metersPerUnit
        let yearDone = runs.filter { year?.contains($0.startDate) ?? false }.reduce(0) { $0 + $1.distance } / unit.metersPerUnit
        let symbol = unit.distanceSymbol
        return VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeading("Goals", style: .overline)
            HStack(spacing: Space.x3) {
                GoalStepperCard("Weekly", accessibilityName: "Weekly goal", value: $weeklyGoal, in: 5...300, step: 5, unit: symbol,
                                caption: "\(weekDone.formatted(.number.precision(.fractionLength(1)))) \(symbol) this week",
                                lowerLabel: "Lower weekly goal", raiseLabel: "Raise weekly goal") {
                    TrackBar(progress: weeklyGoal > 0 ? weekDone / weeklyGoal : 0, height: 6)
                }
                GoalStepperCard("Yearly", accessibilityName: "Yearly goal", value: $yearlyGoal, in: 100...10_000, step: 50, unit: symbol,
                                caption: "\(Int(yearDone).formatted()) \(symbol) so far",
                                lowerLabel: "Lower yearly goal", raiseLabel: "Raise yearly goal") {
                    TrackBar(progress: yearlyGoal > 0 ? yearDone / yearlyGoal : 0, height: 6)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var trainingSection: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeading("Training", style: .overline)
            if dynamicTypeSize.isAccessibilitySize {
                // Five tiles don't fit a row at the largest sizes: plain rows instead.
                GroupedCard(dividerInset: 64) {
                    ForEach(TrainingLink.allCases) { link in
                        trainingLink(link) {
                            CardRow(link.fullTitle, titleWeight: .regular) {
                                SettingIcon(link.symbol)
                            } trailing: {
                                HStack(spacing: Space.x2) {
                                    if link == .workouts, !pro.isPro { TagBadge("Pro") }
                                    DisclosureChevron()
                                }
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: Space.x2) {
                    ForEach(TrainingLink.allCases) { link in
                        trainingLink(link) {
                            TrainingTile(link: link, showsPro: link == .workouts && !pro.isPro)
                        }
                        .accessibilityLabel(link == .workouts && !pro.isPro ? "\(link.fullTitle), Pro" : link.fullTitle)
                    }
                }
            }
        }
    }

    /// A link to the route behind a Training tile, typed so the stack's destinations match it.
    @ViewBuilder
    private func trainingLink<Content: View>(_ link: TrainingLink, @ViewBuilder label: () -> Content) -> some View {
        switch link {
        case .friends: NavigationLink(value: ProgressRoute.friends, label: label).buttonStyle(.plain)
        case .plans: NavigationLink(value: PlanRoute.list, label: label).buttonStyle(.plain)
        case .workouts: NavigationLink(value: PlanRoute.workouts, label: label).buttonStyle(.plain)
        case .challenges: NavigationLink(value: ProgressRoute.challenges, label: label).buttonStyle(.plain)
        case .shoes: NavigationLink(value: ProgressRoute.shoes, label: label).buttonStyle(.plain)
        }
    }
}

/// The places Profile links to, as tiles under Training.
private enum TrainingLink: String, CaseIterable, Identifiable {
    case friends, plans, workouts, challenges, shoes

    var id: Self { self }

    var title: String {
        switch self {
        case .friends: "Friends"
        case .plans: "Plans"
        case .workouts: "Workouts"
        case .challenges: "Challenges"
        case .shoes: "Shoes"
        }
    }

    var fullTitle: String {
        switch self {
        case .plans: "Training plans"
        case .workouts: "Your workouts"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .friends: "person.2"
        case .plans: "calendar.badge.checkmark"
        case .workouts: "repeat"
        case .challenges: "flag"
        case .shoes: "shoe"
        }
    }
}

/// A 76pt raised tile: a symbol in the data color over a short name.
private struct TrainingTile: View {
    let link: TrainingLink
    let showsPro: Bool

    var body: some View {
        VStack(spacing: 7) {
            Image(systemName: link.symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.lane)
                .frame(height: 24)
            Text(link.title)
                .font(.caption.weight(.medium))
                .tracking(-0.1)
                .foregroundStyle(.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 2)
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .contentShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(alignment: .topTrailing) {
            if showsPro {
                TagBadge("Pro")
                    .scaleEffect(0.85, anchor: .topTrailing)
                    .offset(x: 4, y: -7)
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - Voice coach, Health and running

extension ProfileView {
    private var voiceCoachSection: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeading("Voice coach", style: .overline) {
                if voiceCoach {
                    LinkButton("Test voice", systemImage: "play.fill") { testVoice() }
                        // The link keeps its 44pt tap area without pushing the card down.
                        .padding(.vertical, -13)
                }
            }
            GroupedCard(dividerInset: 64) {
                SettingToggleRow("Voice coach", subtitle: "Splits, steps and alerts over music", symbol: "speaker.wave.2", isOn: $voiceCoach)
                if voiceCoach {
                    announceRow
                    includeRow
                }
            }
        }
    }

    private var intervalText: String {
        "\(voiceInterval.formatted()) \(unit.distanceSymbol)"
    }

    private var announceRow: some View {
        Menu {
            Picker("Announce every", selection: $voiceInterval) {
                ForEach([0.5, 1, 2, 5], id: \.self) { value in
                    Text("\(value.formatted()) \(unit.distanceSymbol)").tag(value)
                }
            }
        } label: {
            HStack(spacing: Space.x2) {
                Text("Announce every")
                    .foregroundStyle(.ink)
                Spacer(minLength: Space.x2)
                HStack(spacing: Space.x1) {
                    Text(intervalText)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.inkMuted)
            }
            .font(.body)
            .padding(.leading, 64)
            .padding(.trailing, Space.x4)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .accessibilityLabel("Announce every")
        .accessibilityValue(intervalText)
    }

    private var includeRow: some View {
        HStack(spacing: Space.x2) {
            Text("Include")
                .font(.body)
                .foregroundStyle(.ink)
                .accessibilityHidden(true)
            Spacer(minLength: Space.x2)
            Toggle("Time", isOn: $voiceIncludeTime)
                .toggleStyle(CheckChipToggleStyle())
                .accessibilityLabel("Include time")
            Toggle("Pace", isOn: $voiceIncludePace)
                .toggleStyle(CheckChipToggleStyle())
                .accessibilityLabel("Include pace")
        }
        .padding(.leading, 64)
        .padding(.trailing, Space.x4)
        .frame(minHeight: 56)
    }

    private func testVoice() {
        // The run's own voice, so a test line and a coach line never fight over the audio session.
        tracker.coach.voice.speak(CoachScript.split(
            distance: 5 * unit.metersPerUnit, elapsed: 1_642, averagePace: 328.4, lastSplitPace: 321,
            unit: unit, splitLength: voiceInterval, includeTime: voiceIncludeTime, includePace: voiceIncludePace
        ), force: true)
    }

    private var healthSection: some View {
        let health = HealthSync.shared.isAvailable
        let cloud = iCloudStatus
        return VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeading(health ? "Apple Health and iCloud" : "iCloud", style: .overline)
            GroupedCard(dividerInset: 64) {
                if health {
                    VStack(spacing: 0) {
                        SettingToggleRow("Save runs to Apple Health", subtitle: "iPhone runs, with their route", symbol: "heart",
                                         isOn: Binding(get: { healthSave }, set: setHealthSave))
                        if healthSave {
                            Button(action: saveEarlierRuns) {
                                Text("Save earlier runs too")
                                    .font(.body)
                                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                    .padding(.leading, 64)
                            }
                            .buttonStyle(.strideLink)
                        }
                    }
                }
                CardRow("iCloud sync", subtitle: cloud.subtitle, titleWeight: .regular) {
                    SettingIcon(cloud.on ? "icloud" : "icloud.slash")
                } trailing: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(cloud.on ? Color.success : Color.warning)
                            .frame(width: 8, height: 8)
                        Text(cloud.value)
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }
                    .fixedSize()
                }
                .accessibilityElement(children: .combine)
            }
            if health {
                if healthDenied {
                    Text("Stride isn't allowed to save workouts. Turn it on in the Health app, under Sharing › Apps › Stride.")
                        .font(.footnote)
                        .foregroundStyle(.warning)
                        .padding(.horizontal, Space.x1)
                } else if let healthMessage {
                    Text(healthMessage)
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                        .padding(.horizontal, Space.x1)
                }
            }
        }
    }

    private var runningSection: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeading("Running", style: .overline) {
                if HealthSync.shared.isAvailable {
                    LinkButton("Update from Health", systemImage: "heart") {
                        Task { await updateFromHealth() }
                    }
                    .padding(.vertical, -13)
                    .accessibilityHint("Reads your weight and age from Apple Health")
                }
            }
            GroupedCard(dividerInset: 64) {
                HStack(spacing: Space.x3) {
                    SettingIcon("ruler")
                    Text("Units")
                        .font(.body)
                        .foregroundStyle(.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                    PillPicker("Units", selection: $unit, options: [UnitSystem.metric, .imperial], size: .compact,
                               background: .surfaceSunken) { $0 == .metric ? "Kilometers" : "Miles" }
                }
                .padding(.horizontal, Space.x4)
                .frame(minHeight: 56)
                SettingToggleRow("Auto-pause", symbol: "pause", isOn: $autoPause)
            }
            HStack(spacing: Space.x3) {
                GoalStepperCard("Max HR", accessibilityName: "Max heart rate", value: $maxHeartRate, in: 140...220, step: 1,
                                unit: "bpm", caption: "Sets your 5 zones",
                                lowerLabel: "Lower max heart rate", raiseLabel: "Raise max heart rate") {
                    ZoneScale(height: 6)
                }
                GoalStepperCard("Weight", accessibilityName: "Weight", value: $weightKg, in: 30...200, step: 1,
                                unit: "kg", caption: "For calories",
                                lowerLabel: "Lower weight", raiseLabel: "Raise weight") {
                    // Keeps the two cards the same shape.
                    ZoneScale(height: 6).hidden()
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Space.x1)
            if let bodyMessage {
                Text(bodyMessage)
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                    .padding(.horizontal, Space.x1)
            }
        }
    }
}

// MARK: - Developer and data

extension ProfileView {
    #if DEBUG
    private var developerSection: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            SectionHeading("Developer", style: .overline)
            GroupedCard {
                NavigationLink {
                    DesignSystemGallery()
                } label: {
                    CardRow("Design system", titleWeight: .regular) { DisclosureChevron() }
                }
                .buttonStyle(.plain)
                Button {
                    Task { await SampleData.insert(into: context, weightKg: weightKg) }
                } label: {
                    CardRow("Load sample runs", titleWeight: .regular)
                }
                .buttonStyle(.plain)
            }
        }
    }
    #endif

    private var dataSection: some View {
        VStack(spacing: Space.x3) {
            Button { confirmingDeleteAll = true } label: {
                HStack(spacing: Space.x3) {
                    Image(systemName: "trash")
                        .font(.system(size: 18, weight: .medium))
                        .accessibilityHidden(true)
                    Text("Delete all runs")
                        .font(.body.weight(.semibold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.danger)
                .padding(.horizontal, Space.x4)
                .frame(minHeight: Dimension.control)
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                .contentShape(RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
            Text(versionText)
                .font(.footnote)
                .foregroundStyle(.inkMuted)
                .frame(maxWidth: .infinity)
        }
    }

    /// "Stride 1.0 (1)".
    private var versionText: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String
        return "Stride \(version)\(build.map { " (\($0))" } ?? "")"
    }

    private func deleteAll() {
        // One by one: batch deletes don't reach iCloud.
        (try? context.fetch(FetchDescriptor<Run>()))?.forEach(context.delete)
        (try? context.fetch(FetchDescriptor<RunVitals>()))?.forEach(context.delete)
        (try? context.fetch(FetchDescriptor<Shoe>()))?.forEach(context.delete)
        (try? context.fetch(FetchDescriptor<Challenge>()))?.forEach(context.delete)
        try? context.save()
        ShoeDefaults.set(nil)
    }
}

// MARK: - iCloud and Health

extension ProfileView {
    /// What the iCloud row says: syncing needs both the capability and a signed-in account.
    private var iCloudStatus: (on: Bool, value: String, subtitle: String) {
        let account = FriendsService.shared.account
        guard CloudStore.syncsWithICloud else {
            return (false, "Off", "Runs are kept on this iPhone only")
        }
        switch account {
        case .noAccount:
            return (false, "Signed out", "Sign in to iCloud in Settings to keep your runs on all your iPhones")
        case .restricted, .unavailable:
            return (false, "Unavailable", "iCloud isn't available right now. Runs sync once it is")
        case .available, .unknown:
            return (true, "On", "Kept in step on all your iPhones")
        }
    }

    private func setHealthSave(_ on: Bool) {
        healthSave = on
        healthMessage = nil
        guard on else {
            healthDenied = false
            return
        }
        // Runs from now on; earlier ones (including any recorded while saving was off) only when asked.
        UserDefaults.standard.set(Date.now, forKey: StrideSettings.healthSaveSince)
        Task {
            _ = await HealthSync.shared.requestAuthorization()
            healthDenied = HealthSync.shared.wasDenied
            await HealthSync.shared.exportPending(in: context)
        }
    }

    private func saveEarlierRuns() {
        Task {
            let saved = await HealthSync.shared.exportPending(in: context, includingEarlier: true)
            healthMessage = saved == 0 ? "Every run is already in Health." : "Saved \(saved) \(saved == 1 ? "run" : "runs") to Health."
        }
    }

    private func updateFromHealth() async {
        let body = await HealthSync.shared.readBody()
        var updated: [String] = []
        if let weight = body.weightKg, weight >= 30, weight <= 200 {
            weightKg = weight.rounded()
            updated.append("weight \(Int(weightKg)) kg")
        }
        if let age = body.age, age >= 10, age <= 100 {
            // Tanaka: 208 − 0.7 × age, closer than 220 − age for adults.
            maxHeartRate = min(max((208 - 0.7 * Double(age)).rounded(), 140), 220)
            updated.append("max heart rate \(Int(maxHeartRate)) bpm")
        }
        bodyMessage = updated.isEmpty ? "Health has no weight or birthday to read. Check Health's permissions for Stride."
                                      : "Updated \(updated.joined(separator: " and "))."
    }
}

#Preview {
    ProfileView()
}
