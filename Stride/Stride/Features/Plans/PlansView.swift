import SwiftUI
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
                        PlanCard(plan: plan, isActive: plan.id == activePlanID, completed: completed)
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
    let completed: Set<String>

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack {
                Text(plan.name).font(.title3.bold()).foregroundStyle(.ink)
                Spacer()
                if isActive { StatusChip("Active", indicator: .success) }
            }
            Text(plan.level).metricLabelStyle()
            Text(plan.summary).font(.subheadline).foregroundStyle(.inkMuted)
            if isActive {
                PlanProgressBar(progress: plan.progress(completed: completed))
                    .padding(.top, Space.x1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.x4)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
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

/// A plan's weeks and sessions. Starting a session opens the live run with its steps.
struct PlanDetailView: View {
    let plan: TrainingPlan
    @Environment(RunTracker.self) private var tracker
    @AppStorage(StrideSettings.activePlanID) private var activePlanID = ""
    @AppStorage(StrideSettings.completedPlanSessions) private var completedRaw = ""
    @AppStorage(StrideSettings.autoPause) private var autoPause = true
    @State private var sessionToStart: Workout?
    @State private var confirmingStop = false
    @State private var locationProblem: String?

    private var completed: Set<String> { PlanProgress.completed(from: completedRaw) }
    private var isActive: Bool { activePlanID == plan.id }
    private var next: Workout? { plan.nextSession(completed: completed) }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text(plan.level).metricLabelStyle()
                    Text(plan.summary).font(.body).foregroundStyle(.ink)
                    if isActive {
                        PlanProgressBar(progress: plan.progress(completed: completed))
                            .padding(.top, Space.x2)
                    }
                }
                .padding(.vertical, Space.x2)
                if isActive {
                    Button("Stop this plan", role: .destructive) { confirmingStop = true }
                }
            }
            .listRowBackground(Color.surfaceRaised)

            if !isActive {
                // Its own section, so the full-width button sits under the card instead of cutting its corners.
                Section {
                    Button("Start this plan") { activePlanID = plan.id }
                        .buttonStyle(.stridePrimary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
            }

            ForEach(plan.weeks.indices, id: \.self) { index in
                Section("Week \(index + 1)") {
                    ForEach(plan.weeks[index]) { session in
                        sessionRow(session)
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
            Text(session.detail)
        }
        .locationProblemAlert($locationProblem)
        .confirmationDialog("Stop \(plan.name)?", isPresented: $confirmingStop, titleVisibility: .visible) {
            Button("Stop Plan", role: .destructive) { activePlanID = "" }
        } message: {
            Text("Your completed sessions are kept if you start it again.")
        }
    }

    private func sessionRow(_ session: Workout) -> some View {
        let isDone = completed.contains(session.id)
        let isNext = isActive && session.id == next?.id
        return Button {
            sessionToStart = session
        } label: {
            HStack(spacing: Space.x3) {
                Image(systemName: isDone ? "checkmark.circle.fill" : isNext ? "play.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? Color.success : isNext ? Color.track : Color.lineStrong)
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
            Button(isDone ? "Not done" : "Done") { PlanProgress.set(session.id, done: !isDone); completedRaw = UserDefaults.standard.string(forKey: StrideSettings.completedPlanSessions) ?? "" }
                .tint(isDone ? .lineStrong : .success)
        }
        .accessibilityValue(isDone ? "Done" : isNext ? "Next" : "")
    }

    private func start(_ session: Workout) {
        if let problem = PlanSessionLauncher.locationProblem {
            locationProblem = problem
            return
        }
        if activePlanID.isEmpty { activePlanID = plan.id }
        tracker.start(PlanSessionLauncher.configuration(for: session, autoPause: autoPause))
    }
}
