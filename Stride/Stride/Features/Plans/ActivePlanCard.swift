import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Home: the next session of the active plan, or a way into the plans. With Stride Pro the session
/// shows the runner's own pace; after a break it suggests starting again from the last full week.
struct ActivePlanCard: View {
    @Environment(RunTracker.self) private var tracker
    /// Newest first: the last run dates a break, and best efforts give the paces.
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(StrideSettings.activePlanID) private var activePlanID = ""
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
        if let plan = TrainingPlan.plan(id: activePlanID) {
            let state = PlanState(plan: plan, completedRaw: completedRaw, repeatRaw: repeatRaw,
                                  dismissedLastRun: repeatDismissed, runs: runs)
            let canRun = plan.isFree || ProStore.shared.isPro
            VStack(alignment: .leading, spacing: Space.x3) {
                HStack {
                    Text("Your plan · \(plan.name)").metricLabelStyle()
                    Spacer()
                    NavigationLink("All sessions", value: PlanRoute.plan(plan.id))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.lane)
                }
                if canRun, let week = state.suggestedRepeatWeek {
                    PlanRepeatCallout(week: week, weeksAway: state.weeksAway) {
                        repeatRaw = PlanRepeat(planID: plan.id, week: week, since: .now,
                                               resumeIndex: plan.resumeIndex(completed: state.completed)).rawValue
                    } onDismiss: {
                        repeatDismissed = runs.first?.startDate.timeIntervalSince1970 ?? 0
                    }
                }
                if let next = state.next {
                    if canRun, let repeating = state.repeating {
                        PlanRepeatStatus(week: repeating.week, resumeWeek: state.resumeWeek) {
                        repeatRaw = ""
                        repeatDismissed = runs.first?.startDate.timeIntervalSince1970 ?? 0
                    }
                    }
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Text(next.name).font(.headline).foregroundStyle(.ink)
                        Text(next.detail).font(.subheadline).foregroundStyle(.inkMuted)
                        if canRun, let paces, let intensity = plan.intensity(of: next) {
                            Label(PersonalPaces.line(intensity, paces: paces, unit: unit), systemImage: "gauge.with.needle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.lane)
                                .padding(.top, 2)
                        }
                    }
                    PlanProgressBar(progress: plan.progress(completed: state.completed))
                    if canRun {
                        Button("Start session") { start(next, in: plan) }
                            .buttonStyle(.strideSecondary)
                    } else {
                        // Pro ended: the plan and its progress stay, and pick up where they left off.
                        Button("Continue with Stride Pro") { upsell = .plan(plan.id) }
                            .buttonStyle(.strideSecondary)
                    }
                } else {
                    Label("Plan complete. Well done.", systemImage: "trophy.fill")
                        .font(.headline)
                        .foregroundStyle(.success)
                    if plan.id == "first-5k", let tenK = TrainingPlan.plan(id: "10k") {
                        NavigationLink(value: PlanRoute.plan(tenK.id)) {
                            HStack(spacing: Space.x2) {
                                Text("Next: \(tenK.name) plan").font(.subheadline.weight(.semibold)).foregroundStyle(.lane)
                                if !ProStore.shared.isPro { TagBadge("Pro") }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.inkMuted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(Space.x4)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            .locationProblemAlert($locationProblem)
            .proPaywall($upsell)
            .task(id: PersonalPaces.key(for: runs)) {
                paces = ProStore.shared.isPro ? PersonalPaces.from(runs) : nil
            }
        } else {
            NavigationLink(value: PlanRoute.list) {
                HStack(spacing: Space.x3) {
                    Image(systemName: "calendar.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(.track)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Training plans").font(.headline).foregroundStyle(.ink)
                        Text("First 5K, 10K and Half Marathon, with a coach in your ear.")
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").foregroundStyle(.inkMuted)
                }
                .padding(Space.x4)
                .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            }
            .buttonStyle(.plain)
        }
    }

    private func start(_ session: Workout, in plan: TrainingPlan) {
        if let problem = PlanSessionLauncher.locationProblem {
            locationProblem = problem
            return
        }
        // Fresh, so a run saved a moment ago counts.
        let paces = ProStore.shared.isPro ? PersonalPaces.from(runs) : nil
        tracker.start(PlanSessionLauncher.configuration(for: session, in: plan, paces: paces, autoPause: autoPause))
    }
}
