import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// The training plans, with the active one first.
struct PlansView: View {
    @AppStorage(StrideSettings.activePlanID) private var activePlanID = ""
    @AppStorage(StrideSettings.completedPlanSessions) private var completedRaw = ""

    private var completed: Set<String> { PlanProgress.completed(from: completedRaw) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                ForEach(TrainingPlan.catalog.sorted { ($0.id == activePlanID ? 0 : 1) < ($1.id == activePlanID ? 0 : 1) }) { plan in
                    NavigationLink(value: PlanRoute.plan(plan.id)) {
                        PlanCard(plan: plan, isActive: plan.id == activePlanID, isLocked: !plan.isFree && !ProStore.shared.isPro,
                                 completed: completed)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Space.x4)
        }
        .background(Color.surface)
        .navigationTitle("Training plans")
    }
}

private struct PlanCard: View {
    let plan: TrainingPlan
    let isActive: Bool
    /// A Stride Pro plan the runner can preview but not start.
    let isLocked: Bool
    let completed: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Illustration(name: plan.coverImage, contentMode: .fill)
                .frame(height: 140)
                .frame(maxWidth: .infinity)
                .clipped()
            VStack(alignment: .leading, spacing: Space.x2) {
                HStack {
                    Text(plan.name).font(.title3.bold()).foregroundStyle(.ink)
                    Spacer()
                    if isActive { StatusChip("Active", indicator: .success) } else if isLocked { TagBadge("Pro") }
                }
                Text(plan.level).metricLabelStyle()
                Text(plan.summary).font(.subheadline).foregroundStyle(.inkMuted)
                if isActive {
                    PlanProgressBar(progress: plan.progress(completed: completed))
                        .padding(.top, Space.x1)
                }
            }
            .padding(Space.x4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }
}

struct PlanProgressBar: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.surfaceSunken)
                    Capsule().fill(progress >= 1 ? Color.success : Color.track).frame(width: geo.size.width * min(progress, 1))
                }
            }
            .frame(height: 8)
            Text("\(Int((progress * 100).rounded()))% done")
                .font(.caption)
                .foregroundStyle(.inkMuted)
        }
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

    private var isActive: Bool { activePlanID == plan.id }
    /// A Stride Pro plan without Pro: its weeks stay browsable, but nothing starts or gets marked.
    private var isLocked: Bool { !plan.isFree && !ProStore.shared.isPro }

    var body: some View {
        let state = PlanState(plan: plan, completedRaw: completedRaw, repeatRaw: repeatRaw,
                              dismissedLastRun: repeatDismissed, runs: runs)
        let completed = state.completed
        List {
            Section {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Illustration(name: plan.coverImage, contentMode: .fill)
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.sm))
                        .padding(.bottom, Space.x1)
                    Text(plan.level).metricLabelStyle()
                    Text(plan.summary).font(.body).foregroundStyle(.ink)
                    if isActive {
                        PlanProgressBar(progress: plan.progress(completed: completed))
                            .padding(.top, Space.x2)
                    }
                }
                .padding(.vertical, Space.x2)
                if isActive, !isLocked, let repeating = state.repeating {
                    PlanRepeatStatus(week: repeating.week, resumeWeek: state.resumeWeek) {
                        repeatRaw = ""
                        repeatDismissed = runs.first?.startDate.timeIntervalSince1970 ?? 0
                    }
                }
                if isActive {
                    Button("Stop this plan", role: .destructive) { confirmingStop = true }
                }
            }
            .listRowBackground(Color.surfaceRaised)

            if isActive, !isLocked, let week = state.suggestedRepeatWeek {
                Section {
                    PlanRepeatCallout(week: week, weeksAway: state.weeksAway) {
                        repeatRaw = PlanRepeat(planID: plan.id, week: week, since: .now,
                                               resumeIndex: plan.resumeIndex(completed: state.completed)).rawValue
                    } onDismiss: {
                        repeatDismissed = runs.first?.startDate.timeIntervalSince1970 ?? 0
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
            }

            if isLocked {
                Section {
                    Button("Unlock with Stride Pro") { upsell = .plan(plan.id) }
                        .buttonStyle(.stridePrimary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                } footer: {
                    Text(isActive ? "Your progress is kept. Continue any time with Stride Pro." : "First 5K is free for everyone.")
                }
            } else if !isActive {
                // Its own section, so the full-width button sits under the card instead of cutting its corners.
                Section {
                    Button("Start this plan") { makeActive() }
                        .buttonStyle(.stridePrimary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }

            if plan.usesPersonalPaces {
                Section {
                    PersonalPacesRows(paces: paces, unit: unit, isLocked: !ProStore.shared.isPro) { upsell = .plan(plan.id) }
                } header: {
                    Text("Your paces")
                } footer: {
                    if ProStore.shared.isPro, paces != nil {
                        Text("From your best efforts, and they update as those improve. The coach holds you to them on tempo and interval sessions; easy runs are by feel.")
                    }
                }
                .listRowBackground(Color.surfaceRaised)
            }

            ForEach(plan.weeks.indices, id: \.self) { index in
                Section("Week \(index + 1)") {
                    ForEach(plan.weeks[index]) { session in
                        sessionRow(session, completed: completed, next: state.next)
                    }
                }
                .listRowBackground(Color.surfaceRaised)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Color.surface)
        .navigationTitle(plan.name)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(sessionToStart?.name ?? "", isPresented: Binding(get: { sessionToStart != nil }, set: { if !$0 { sessionToStart = nil } }),
                            titleVisibility: .visible, presenting: sessionToStart) { session in
            Button("Start run") { start(session) }
        } message: { session in
            Text(sessionMessage(session))
        }
        .locationProblemAlert($locationProblem)
        .proPaywall($upsell)
        .confirmationDialog("Stop \(plan.name)?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop Plan", role: .destructive) {
                activePlanID = ""
                repeatRaw = ""
            }
        } message: {
            Text("Your completed sessions are kept if you start it again.")
        }
        .task(id: PersonalPaces.key(for: runs)) {
            paces = ProStore.shared.isPro && plan.usesPersonalPaces ? PersonalPaces.from(runs) : nil
        }
    }

    private func sessionRow(_ session: Workout, completed: Set<String>, next: Workout?) -> some View {
        let isDone = completed.contains(session.id)
        let isNext = isActive && session.id == next?.id
        return Button {
            if isLocked { upsell = .plan(plan.id) } else { sessionToStart = session }
        } label: {
            HStack(spacing: Space.x3) {
                // Next first: a session being run again after a break is both done and next.
                Image(systemName: isNext ? "play.circle.fill" : isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isNext ? Color.track : isDone ? Color.success : Color.lineStrong)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.name)
                        .font(.headline)
                        .foregroundStyle(.ink)
                    Text(session.detail)
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                }
                Spacer()
                if isNext {
                    Text("Next").font(.caption.weight(.semibold)).foregroundStyle(.track)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .swipeActions {
            if !isLocked {
                Button(isDone ? "Not done" : "Done") { PlanProgress.set(session.id, done: !isDone); completedRaw = UserDefaults.standard.string(forKey: StrideSettings.completedPlanSessions) ?? "" }
                    .tint(isDone ? .lineStrong : .success)
            }
        }
        .accessibilityValue(isDone ? "Done" : isNext ? "Next" : "")
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
        guard !isLocked, ProStore.shared.isPro, let paces, let intensity = plan.intensity(of: session) else {
            return session.detail
        }
        let line = PersonalPaces.line(intensity, paces: paces, unit: unit)
        return intensity == .easy
            ? "\(session.detail)\n\(line), by feel."
            : "\(session.detail)\n\(line). The coach tells you when you drift off it."
    }
}
