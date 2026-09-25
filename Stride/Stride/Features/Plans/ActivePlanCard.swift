import SwiftUI
import StrideKit
import StrideUI

/// Home: the next session of the active plan, or a way into the plans.
struct ActivePlanCard: View {
    @Environment(RunTracker.self) private var tracker
    @AppStorage(StrideSettings.activePlanID) private var activePlanID = ""
    @AppStorage(StrideSettings.completedPlanSessions) private var completedRaw = ""
    @AppStorage(StrideSettings.autoPause) private var autoPause = true
    @State private var locationProblem: String?

    var body: some View {
        if let plan = TrainingPlan.plan(id: activePlanID) {
            let completed = PlanProgress.completed(from: completedRaw)
            VStack(alignment: .leading, spacing: Space.x3) {
                HStack {
                    Text("Your plan · \(plan.name)").metricLabelStyle()
                    Spacer()
                    NavigationLink("All sessions", value: PlanRoute.plan(plan.id))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.lane)
                }
                if let next = plan.nextSession(completed: completed) {
                    VStack(alignment: .leading, spacing: Space.x1) {
                        Text(next.name).font(.headline).foregroundStyle(.ink)
                        Text(next.detail).font(.subheadline).foregroundStyle(.inkMuted)
                    }
                    PlanProgressBar(progress: plan.progress(completed: completed))
                    Button("Start session") { start(next) }
                        .buttonStyle(.strideSecondary)
                } else {
                    Label("Plan complete. Well done!", systemImage: "trophy.fill")
                        .font(.headline)
                        .foregroundStyle(.success)
                }
            }
            .padding(Space.x4)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            .locationProblemAlert($locationProblem)
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

    private func start(_ session: Workout) {
        if let problem = PlanSessionLauncher.locationProblem {
            locationProblem = problem
            return
        }
        tracker.start(PlanSessionLauncher.configuration(for: session, autoPause: autoPause))
    }
}
