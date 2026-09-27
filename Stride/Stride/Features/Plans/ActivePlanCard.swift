import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Home: "Your plan" with the next session of the active plan, or a way into the plans. With Stride
/// Pro the session shows the runner's own pace; after a break it suggests starting again from the
/// last full week.
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
            VStack(alignment: .leading, spacing: Space.x1) {
                SectionHeading("Your plan") {
                    NavigationLink(value: PlanRoute.plan(plan.id)) {
                        LinkLabel("All sessions")
                    }
                    .buttonStyle(.strideLink)
                }
                card(plan, state: state, canRun: canRun)
            }
            .locationProblemAlert($locationProblem)
            .proPaywall($upsell)
            .task(id: PersonalPaces.key(for: runs)) {
                paces = ProStore.shared.isPro ? PersonalPaces.from(runs) : nil
            }
        } else {
            plansRow
        }
    }

    private func card(_ plan: TrainingPlan, state: PlanState, canRun: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            if canRun, let week = state.suggestedRepeatWeek {
                PlanRepeatCallout(week: week, weeksAway: state.weeksAway) {
                    repeatRaw = PlanRepeat(planID: plan.id, week: week, since: .now,
                                           resumeIndex: plan.resumeIndex(completed: state.completed)).rawValue
                } onDismiss: {
                    repeatDismissed = runs.first?.startDate.timeIntervalSince1970 ?? 0
                }
            }
            if let next = state.next {
                HStack(spacing: 14) {
                    ArtThumbnail(name: plan.coverImage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(plan.name) · Next session").metricLabelStyle()
                        Text(next.name)
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.ink)
                        // One line, as drawn and as in Training plans: "5 × 800 m at 4'45" /km" with Pro.
                        Text(PlanText.detail(next, in: plan, paces: canRun ? paces : nil, raceTime: nil, unit: unit,
                                             withRecovery: false))
                            .font(.subheadline)
                            .foregroundStyle(.inkMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityElement(children: .combine)

                if canRun, let repeating = state.repeating {
                    PlanRepeatStatus(week: repeating.week, resumeWeek: state.resumeWeek) {
                        repeatRaw = ""
                        repeatDismissed = runs.first?.startDate.timeIntervalSince1970 ?? 0
                    }
                }
                progress(plan, completed: state.completed, next: next)

                if canRun {
                    Button { start(next, in: plan) } label: {
                        Label("Start session", systemImage: "play.fill")
                    }
                    .buttonStyle(.strideSecondary)
                } else {
                    // Pro ended: the plan and its progress stay, and pick up where they left off.
                    Button("Continue with Stride Pro") { upsell = .plan(plan.id) }
                        .buttonStyle(.strideSecondary)
                }
            } else {
                complete(plan)
            }
        }
        .raisedCard()
    }

    /// "Week 3 of 8 · 38%" over the plan's progress bar.
    private func progress(_ plan: TrainingPlan, completed: Set<String>, next: Workout) -> some View {
        let progress = plan.progress(completed: completed)
        let week = (plan.week(of: next.id) ?? 0) + 1
        let percent = Int((progress * 100).rounded())
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Week \(week) of \(plan.weeks.count)")
                    .foregroundStyle(.inkMuted)
                Spacer(minLength: Space.x2)
                Text(verbatim: "\(percent)%")
                    .foregroundStyle(.ink)
            }
            .font(.footnote.weight(.medium))
            .monospacedDigit()
            TrackBar(progress: progress, height: 8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Plan progress")
        .accessibilityValue("Week \(week) of \(plan.weeks.count), \(percent) percent")
    }

    @ViewBuilder private func complete(_ plan: TrainingPlan) -> some View {
        HStack(spacing: 14) {
            ArtThumbnail(name: plan.coverImage)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(plan.name) · Complete").metricLabelStyle()
                Label("Plan complete. Well done.", systemImage: "trophy.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.success)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
        if plan.id == "first-5k", let tenK = TrainingPlan.plan(id: "10k") {
            NavigationLink(value: PlanRoute.plan(tenK.id)) {
                HStack(spacing: Space.x2) {
                    Text("Next: \(tenK.name) plan")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.lane)
                    if !ProStore.shared.isPro { TagBadge("Pro") }
                    Spacer(minLength: 0)
                    DisclosureChevron()
                }
                .frame(minHeight: Dimension.hitMin)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    /// No plan yet: the plans, with a cover.
    private var plansRow: some View {
        NavigationLink(value: PlanRoute.list) {
            HStack(spacing: 14) {
                ArtThumbnail(name: "planFirst5k")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Training plans")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.ink)
                    Text("First 5K, 10K and Half Marathon, with a coach in your ear.")
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
