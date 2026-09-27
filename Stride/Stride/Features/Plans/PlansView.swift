import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// The training plans: the runner's plan first, with its next session, then the others.
struct PlansView: View {
    @AppStorage(StrideSettings.activePlanID) private var activePlanID = ""

    var body: some View {
        let active = TrainingPlan.plan(id: activePlanID)
        let others = TrainingPlan.catalog.filter { $0.id != active?.id }
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                Text("A coach in your ear, on iPhone and Apple Watch.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if let active {
                    ActivePlanHero(plan: active)
                }
                if !others.isEmpty {
                    VStack(alignment: .leading, spacing: Space.x3) {
                        SectionHeading(active == nil ? "Pick a plan" : "More plans")
                        GroupedCard(dividerInset: 0) {
                            ForEach(others) { plan in
                                PlanListRow(plan: plan)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, Space.x4)
            .padding(.bottom, Space.x5)
        }
        .background(Color.surface)
        .navigationTitle("Training plans")
    }
}

/// The runner's plan: its cover, how far along it is week by week, the next session and a way to
/// start it, and the way into every week.
private struct ActivePlanHero: View {
    let plan: TrainingPlan
    @Environment(RunTracker.self) private var tracker
    /// Newest first: the last run dates a break, and best efforts give the paces.
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(StrideSettings.completedPlanSessions) private var completedRaw = ""
    @AppStorage(StrideSettings.planRepeat) private var repeatRaw = ""
    @AppStorage(StrideSettings.planRepeatDismissed) private var repeatDismissed = 0.0
    @AppStorage(StrideSettings.autoPause) private var autoPause = true
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var locationProblem: String?
    @State private var upsell: ProFeature?
    /// The runner's paces, with Stride Pro only.
    @State private var paces: TrainingPaces?

    var body: some View {
        let state = PlanState(plan: plan, completedRaw: completedRaw, repeatRaw: repeatRaw,
                              dismissedLastRun: repeatDismissed, runs: runs)
        // Pro ended: the plan and its progress stay, and pick up where they left off with Pro.
        let canRun = plan.isFree || ProStore.shared.isPro
        let currentWeek = state.next.flatMap { plan.week(of: $0.id) }
        let percent = Int((plan.progress(completed: state.completed) * 100).rounded())
        VStack(alignment: .leading, spacing: 0) {
            ArtThumbnail(name: plan.coverImage, width: nil, height: 201, cornerRadius: 0)
                .overlay(alignment: .topLeading) {
                    StatusChip("Your plan", indicator: .success)
                        .padding(Space.x3)
                }
            VStack(alignment: .leading, spacing: Space.x3) {
                VStack(alignment: .leading, spacing: Space.x1) {
                    Text(plan.level).metricLabelStyle()
                    Text(plan.name)
                        .font(.title2.bold())
                        .foregroundStyle(.ink)
                        .padding(.top, 2)
                        .accessibilityAddTraits(.isHeader)
                    Text(plan.summary)
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(alignment: .leading, spacing: Space.x2) {
                    SegmentedProgressBar(fractions: PlanText.weekFractions(plan, completed: state.completed))
                    HStack {
                        Text("\(percent)% done").font(.footnote.weight(.semibold)).foregroundStyle(.ink)
                        Spacer(minLength: Space.x2)
                        Text(currentWeek.map { "Week \($0 + 1) of \(plan.weeks.count)" } ?? "All \(plan.weeks.count) weeks done")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.inkMuted)
                    }
                }
                .accessibilityElement(children: .combine)

                if let next = state.next {
                    nextSession(next, canRun: canRun)
                    if canRun {
                        Button { start(next) } label: {
                            Label("Start session", systemImage: "play.fill")
                        }
                        .buttonStyle(.stridePrimary)
                    } else {
                        Button("Continue with Stride Pro") { upsell = .plan(plan.id) }
                            .buttonStyle(.stridePrimary)
                    }
                } else {
                    HStack(spacing: Space.x3) {
                        IconBadge("trophy.fill", style: .tinted(.success))
                        Text("Plan complete. Well done.")
                            .font(.headline)
                            .foregroundStyle(.ink)
                    }
                    .raisedCard(padding: Space.x3, fill: .surfaceSunken)
                }

                NavigationLink(value: PlanRoute.plan(plan.id)) {
                    LinkLabel("All weeks and sessions", showsChevron: true)
                }
                .buttonStyle(.strideLink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, -Space.x2)
            }
            .padding(Space.x4)
        }
        .background(Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .locationProblemAlert($locationProblem)
        .proPaywall($upsell)
        .task(id: PersonalPaces.key(for: runs)) {
            paces = ProStore.shared.isPro ? PersonalPaces.from(runs) : nil
        }
    }

    /// The next session on a sunken well: what it is, the pace with Stride Pro, and about how long.
    private func nextSession(_ next: Workout, canRun: Bool) -> some View {
        let paces = canRun ? self.paces : nil
        let steps = paces.map { plan.personalized(next, paces: $0).steps } ?? next.steps
        let estimate = paces.map { WorkoutEstimate(steps: steps, paces: $0) } ?? WorkoutEstimate(steps: steps)
        let detail = PlanText.detail(next, in: plan, paces: paces, raceTime: nil, unit: unit, withRecovery: false)
        return HStack(spacing: Space.x3) {
            IconBadge(steps.count > 1 ? "repeat" : "figure.run", style: .brand, size: 40)
            VStack(alignment: .leading, spacing: 0) {
                Text("Next session").metricLabelStyle()
                Text(next.name)
                    .font(.headline)
                    .foregroundStyle(.ink)
                    .padding(.top, 2)
                Text("\(detail) · about \(PlanText.minutes(estimate.duration))")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .raisedCard(padding: Space.x3, fill: .surfaceSunken)
        .accessibilityElement(children: .combine)
    }

    private func start(_ session: Workout) {
        if let problem = PlanSessionLauncher.locationProblem {
            locationProblem = problem
            return
        }
        // Fresh, so a run saved a moment ago counts.
        let paces = ProStore.shared.isPro ? PersonalPaces.from(runs) : nil
        tracker.start(PlanSessionLauncher.configuration(for: session, in: plan, paces: paces, autoPause: autoPause))
    }
}

/// A plan in the list: its cover, name, level and length, and what it builds to.
private struct PlanListRow: View {
    let plan: TrainingPlan

    var body: some View {
        // A Stride Pro plan the runner can preview but not start.
        let isLocked = !plan.isFree && !ProStore.shared.isPro
        NavigationLink(value: PlanRoute.plan(plan.id)) {
            HStack(spacing: Space.x3) {
                ArtThumbnail(name: plan.coverImage, width: 104, height: 58)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.x2) {
                        Text(plan.name).font(.headline).foregroundStyle(.ink)
                        if isLocked { TagBadge("Pro") }
                    }
                    Text(shortLevel).font(.footnote.weight(.medium)).foregroundStyle(.inkMuted)
                    Text(plan.summary)
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                DisclosureChevron()
            }
            .padding(.vertical, Space.x3)
            .padding(.leading, Space.x3)
            .padding(.trailing, Space.x4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    /// "Beginner · 6 weeks", without the runs a week.
    private var shortLevel: String {
        plan.level.components(separatedBy: " · ").prefix(2).joined(separator: " · ")
    }
}

/// A plan's progress as a bar in the data color, and the share done under it.
struct PlanProgressBar: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            TrackBar(progress: progress, tint: progress >= 1 ? .success : .lane)
            Text("\(Int((progress * 100).rounded()))% done")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A plan's weeks and sessions. Starting a session opens the live run with its steps. With Stride Pro,
/// the runner's own paces; after a break, a way to start again from the last full week.
struct PlanDetailView: View {
    let plan: TrainingPlan
    @Environment(RunTracker.self) private var tracker
    /// Newest first: the last run dates a break, and best efforts give the paces.
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(StrideSettings.activePlanID) private var activePlanID = ""
    @AppStorage(StrideSettings.completedPlanSessions) private var completedRaw = ""
    @AppStorage(StrideSettings.planRepeat) private var repeatRaw = ""
    @AppStorage(StrideSettings.planRepeatDismissed) private var repeatDismissed = 0.0
    @AppStorage(StrideSettings.autoPause) private var autoPause = true
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var sessionToStart: Workout?
    @State private var confirmingStop = false
    @State private var locationProblem: String?
    @State private var upsell: ProFeature?
    /// The runner's paces, with Stride Pro only.
    @State private var paces: TrainingPaces?
    /// The predicted time for the race the plan ends with, with Stride Pro only.
    @State private var raceTime: TimeInterval?
    /// The week shown open: the current one to begin with.
    @State private var openWeek: Int?
    @State private var openedCurrentWeek = false

    private var isActive: Bool { activePlanID == plan.id }
    /// A Stride Pro plan without Pro: its weeks stay browsable, but nothing starts or gets marked.
    private var isLocked: Bool { !plan.isFree && !ProStore.shared.isPro }
    private var isPro: Bool { ProStore.shared.isPro }

    var body: some View {
        let state = planState
        let currentWeek = state.next.flatMap { plan.week(of: $0.id) }
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                overview(state: state, currentWeek: currentWeek)

                if isActive, !isLocked, let week = state.suggestedRepeatWeek {
                    PlanRepeatCallout(week: week, weeksAway: state.weeksAway) {
                        repeatRaw = PlanRepeat(planID: plan.id, week: week, since: .now,
                                               resumeIndex: plan.resumeIndex(completed: state.completed)).rawValue
                    } onDismiss: {
                        repeatDismissed = runs.first?.startDate.timeIntervalSince1970 ?? 0
                    }
                }

                if isActive {
                    nextSessionCard(state)
                }

                if plan.usesPersonalPaces {
                    PersonalPacesCard(paces: paces, unit: unit, isLocked: !isPro) { upsell = .plan(plan.id) }
                }

                weeks(state: state, currentWeek: currentWeek)
            }
            .padding(.horizontal, Space.x4)
            .padding(.top, Space.x2)
            .padding(.bottom, Space.x5)
        }
        .background(Color.surface)
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isActive {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Stop this plan", systemImage: "stop.circle", role: .destructive) { confirmingStop = true }
                    } label: {
                        Label("Plan options", systemImage: "ellipsis")
                    }
                }
            }
        }
        .confirmationDialog(sessionToStart?.name ?? "",
                            isPresented: Binding(get: { sessionToStart != nil }, set: { if !$0 { sessionToStart = nil } }),
                            titleVisibility: .visible, presenting: sessionToStart) { session in
            Button("Start run") { start(session) }
        } message: { session in
            Text(sessionMessage(session))
        }
        .locationProblemAlert($locationProblem)
        .proPaywall($upsell)
        .confirmationDialog("Stop \(plan.name)?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop plan", role: .destructive) {
                activePlanID = ""
                repeatRaw = ""
            }
        } message: {
            Text("Your completed sessions are kept if you start it again.")
        }
        .task(id: PersonalPaces.key(for: runs)) {
            guard ProStore.shared.isPro else {
                paces = nil
                raceTime = nil
                return
            }
            let predictions = RacePredictor.predict(from: runs.map(\.recordEntry))
            paces = plan.usesPersonalPaces ? predictions?.trainingPaces : nil
            raceTime = PlanText.race(of: plan).flatMap { predictions?[$0]?.time }
        }
        .onAppear {
            guard !openedCurrentWeek else { return }
            openedCurrentWeek = true
            openWeek = planState.next.flatMap { plan.week(of: $0.id) } ?? 0
        }
        .sensoryFeedback(.selection, trigger: completedRaw)
    }

    private var planState: PlanState {
        PlanState(plan: plan, completedRaw: completedRaw, repeatRaw: repeatRaw,
                  dismissedLastRun: repeatDismissed, runs: runs)
    }

    // MARK: Overview

    private func overview(state: PlanState, currentWeek: Int?) -> some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            ArtThumbnail(name: plan.coverImage, width: nil, height: 172, cornerRadius: Radius.md)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text(plan.level).metricLabelStyle()
                Text(plan.summary)
                    .font(.body)
                    .foregroundStyle(.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if isActive {
                VStack(alignment: .leading, spacing: Space.x2) {
                    HStack(alignment: .firstTextBaseline) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("\(Int((plan.progress(completed: state.completed) * 100).rounded()))%")
                                .font(.metricMedium)
                                .monospacedDigit()
                                .foregroundStyle(.ink)
                            Text("done").font(.subheadline).foregroundStyle(.inkMuted)
                        }
                        Spacer(minLength: Space.x2)
                        Text(currentWeek.map { "Week \($0 + 1) of \(plan.weeks.count)" } ?? "All \(plan.weeks.count) weeks done")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.ink)
                    }
                    SegmentedProgressBar(fractions: PlanText.weekFractions(plan, completed: state.completed),
                                         track: .surfaceRaised)
                }
                .accessibilityElement(children: .combine)
            } else if isLocked {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Button("Unlock with Stride Pro") { upsell = .plan(plan.id) }
                        .buttonStyle(.stridePrimary)
                    Text("First 5K is free for everyone.")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
            } else {
                Button("Start this plan") { makeActive() }
                    .buttonStyle(.stridePrimary)
            }
        }
    }

    // MARK: Next session

    @ViewBuilder
    private func nextSessionCard(_ state: PlanState) -> some View {
        if let next = state.next {
            let paces = isPro ? self.paces : nil
            let steps = paces.map { plan.personalized(next, paces: $0).steps } ?? next.steps
            VStack(alignment: .leading, spacing: Space.x3) {
                if !isLocked, let repeating = state.repeating {
                    PlanRepeatStatus(week: repeating.week, resumeWeek: state.resumeWeek) {
                        repeatRaw = ""
                        repeatDismissed = runs.first?.startDate.timeIntervalSince1970 ?? 0
                    }
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text("Next session").metricLabelStyle()
                    Text(next.name)
                        .font(.title2.bold())
                        .foregroundStyle(.ink)
                        .padding(.top, Space.x1)
                    Text(detail(next))
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 2)
                }
                .accessibilityElement(children: .combine)
                VStack(alignment: .leading, spacing: Space.x2) {
                    StepStrip(steps: steps, paces: paces, style: .shaped, height: 28,
                              accessibilityLabel: StepStrip.summary(of: steps, unit: unit))
                    let length = Text(PlanText.length(of: steps, paces: paces, unit: unit))
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.ink)
                    if steps.count > 1 {
                        ViewThatFits(in: .horizontal) {
                            HStack {
                                StepLegend(warmUpTitle: "Warm-up", spacing: Space.x3)
                                Spacer(minLength: Space.x2)
                                length
                            }
                            VStack(alignment: .leading, spacing: Space.x1) {
                                StepLegend(warmUpTitle: "Warm-up", spacing: Space.x3)
                                length
                            }
                        }
                    } else {
                        length.frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .raisedCard(padding: Space.x3, fill: .surfaceSunken)
                if isLocked {
                    Button("Continue with Stride Pro") { upsell = .plan(plan.id) }
                        .buttonStyle(.stridePrimary)
                    Text("Your progress is kept. Continue any time with Stride Pro.")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                } else {
                    Button { start(next) } label: {
                        Label("Start session", systemImage: "play.fill")
                    }
                    .buttonStyle(.stridePrimary)
                }
            }
            .raisedCard()
        } else {
            HStack(spacing: Space.x3) {
                IconBadge("trophy.fill", style: .tinted(.success))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Plan complete. Well done.").font(.headline).foregroundStyle(.ink)
                    Text("Run any session again from the weeks below.")
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
            }
            .raisedCard()
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Weeks

    private func weeks(state: PlanState, currentWeek: Int?) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            SectionHeading("Weeks")
            VStack(spacing: 0) {
                ForEach(plan.weeks.indices, id: \.self) { index in
                    if index > 0 { Hairline() }
                    week(index, state: state, isCurrent: isActive && index == currentWeek)
                }
            }
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            Text("Sessions you run from here are marked done for you.")
                .font(.footnote)
                .foregroundStyle(.inkMuted)
        }
    }

    private func week(_ index: Int, state: PlanState, isCurrent: Bool) -> some View {
        let sessions = plan.weeks[index]
        let done = sessions.filter { state.completed.contains($0.id) }.count
        let isOpen = openWeek == index
        let caption: String = if done == sessions.count, !sessions.isEmpty {
            "\(done) of \(sessions.count) done"
        } else if isCurrent {
            "This week · \(done) of \(sessions.count) done"
        } else if done > 0 {
            "\(done) of \(sessions.count) done"
        } else {
            PlanText.weekSummary(sessions, in: plan, unit: unit)
        }
        return VStack(spacing: 0) {
            Button {
                withAnimation(.snappy) { openWeek = isOpen ? nil : index }
            } label: {
                HStack(spacing: Space.x3) {
                    WeekBadge(fraction: sessions.isEmpty ? 0 : Double(done) / Double(sessions.count), isCurrent: isCurrent)
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Week \(index + 1)").font(.headline).foregroundStyle(.ink)
                        Text(caption)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(isCurrent ? Color.lane : Color.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.inkMuted)
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, Space.x4)
                .padding(.vertical, 6)
                .frame(minHeight: 52)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isOpen ? "Hides its sessions" : "Shows its sessions")

            if isOpen {
                VStack(spacing: 0) {
                    ForEach(sessions) { session in
                        sessionRow(session, completed: state.completed, next: state.next)
                    }
                }
                // Under the week's title, past the badge.
                .padding(.leading, Space.x4 + 24 + Space.x3)
                .padding(.trailing, Space.x4)
                .padding(.bottom, Space.x2)
            }
        }
    }

    private func sessionRow(_ session: Workout, completed: Set<String>, next: Workout?) -> some View {
        let isDone = completed.contains(session.id)
        let isNext = isActive && session.id == next?.id
        let title = PlanText.sessionTitle(session)
        return HStack(spacing: Space.x2) {
            Button {
                if isLocked { upsell = .plan(plan.id) } else { sessionToStart = session }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: Space.x2) {
                        Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                        if isNext { SoftBadge("Next", tone: .brand, uppercase: true) }
                    }
                    Text(detail(session))
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(isDone ? "Done" : isNext ? "Next" : "")
            .accessibilityHint(isLocked ? "Needs Stride Pro" : "Starts this session")

            Button {
                toggle(session, done: !isDone)
            } label: {
                SessionMark(isDone: isDone, isNext: isNext)
                    .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, -10)
            .accessibilityLabel(isDone ? "\(title), done. Mark as not done" : "\(title). Mark as done")
        }
        .frame(minHeight: 56)
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: Actions

    /// The session in words, with the runner's pace and predicted race time when Pro gives them.
    private func detail(_ session: Workout) -> String {
        PlanText.detail(session, in: plan, paces: isPro ? paces : nil, raceTime: isPro ? raceTime : nil, unit: unit)
    }

    private func toggle(_ session: Workout, done: Bool) {
        guard !isLocked else {
            upsell = .plan(plan.id)
            return
        }
        PlanProgress.set(session.id, done: done)
        completedRaw = UserDefaults.standard.string(forKey: StrideSettings.completedPlanSessions) ?? ""
    }

    private func start(_ session: Workout) {
        guard !isLocked else {
            upsell = .plan(plan.id)
            return
        }
        if let problem = PlanSessionLauncher.locationProblem {
            locationProblem = problem
            return
        }
        if activePlanID.isEmpty { makeActive() }
        // Fresh, so a run saved a moment ago counts.
        let paces = ProStore.shared.isPro ? PersonalPaces.from(runs) : nil
        tracker.start(PlanSessionLauncher.configuration(for: session, in: plan, paces: paces, autoPause: autoPause))
    }

    /// A repeat belongs to the plan it was started in; switching plans drops it.
    private func makeActive() {
        activePlanID = plan.id
        repeatRaw = ""
    }

    /// The session, and with Stride Pro the pace it's run at.
    private func sessionMessage(_ session: Workout) -> String {
        guard !isLocked, isPro, let paces, let intensity = plan.intensity(of: session) else {
            return session.detail
        }
        let line = PersonalPaces.line(intensity, paces: paces, unit: unit)
        return intensity == .easy
            ? "\(session.detail)\n\(line), by feel."
            : "\(session.detail)\n\(line). The coach tells you when you drift off it."
    }
}

/// A week's state at a glance: a tick when every session is done, a filling ring for the current
/// week, an empty ring otherwise.
private struct WeekBadge: View {
    let fraction: Double
    let isCurrent: Bool

    var body: some View {
        ZStack {
            if fraction >= 1 {
                Circle().fill(Color.success)
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.onTrack)
            } else if isCurrent {
                // A pie: a stroke as wide as the radius it's drawn on.
                Circle()
                    .trim(from: 0, to: min(max(fraction, 0), 1))
                    .stroke(Color.lane, lineWidth: 10)
                    .frame(width: 10, height: 10)
                    .rotationEffect(.degrees(-90))
                Circle().strokeBorder(Color.lane, lineWidth: 2)
            } else {
                Circle().strokeBorder(Color.lineStrong, lineWidth: 2)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }
}

/// A session's state, and the control that marks it done: a play mark on the next one, a tick on
/// done ones, an empty ring otherwise.
private struct SessionMark: View {
    let isDone: Bool
    let isNext: Bool

    var body: some View {
        ZStack {
            // Next first: a session being run again after a break is both done and next.
            if isNext {
                Circle().fill(Color.track)
                Image(systemName: "play.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.onTrack)
                    .offset(x: 1)
            } else if isDone {
                Circle().fill(Color.success)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.onTrack)
            } else {
                Circle().strokeBorder(Color.lineStrong, lineWidth: 2)
            }
        }
        .frame(width: 26, height: 26)
    }
}
