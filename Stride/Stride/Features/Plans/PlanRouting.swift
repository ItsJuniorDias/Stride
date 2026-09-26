import SwiftUI
import CoreLocation
import StrideKit

/// Value-based navigation to the plans, so a pushed plan screen doesn't depend on the link that
/// pushed it (the Home card changes shape when a plan starts or stops).
enum PlanRoute: Hashable {
    case list
    case plan(String)
    /// The runner's own interval workouts.
    case workouts
}

extension View {
    /// Registers where plan routes lead. Add once per NavigationStack that links to plans.
    func planDestinations() -> some View {
        navigationDestination(for: PlanRoute.self) { route in
            switch route {
            case .list:
                PlansView()
            case .plan(let id):
                if let plan = TrainingPlan.plan(id: id) {
                    PlanDetailView(plan: plan)
                }
            case .workouts:
                CustomWorkoutsView()
            }
        }
    }
}

/// Starting a plan session from Home or a plan screen, with the same location checks as the Run tab.
enum PlanSessionLauncher {
    /// A plan session follows its own steps; the Run tab's remembered target pace doesn't apply. With
    /// Stride Pro, `paces` (the runner's own, when there are enough runs) put a target on tempo and
    /// interval steps for the coach's pace alerts; without Pro the session runs exactly as written.
    static func configuration(for session: Workout, in plan: TrainingPlan, paces: TrainingPaces?,
                              autoPause: Bool) -> RunTracker.Configuration {
        var workout = session
        if ProStore.shared.isPro, let paces { workout = plan.personalized(session, paces: paces) }
        var configuration = RunTracker.Configuration(type: workout.steps.count > 1 ? .intervals : .free,
                                                     workoutName: workout.name, autoPause: autoPause)
        configuration.workout = workout
        configuration.planSessionID = workout.id
        return configuration
    }

    /// Why a run can't record properly right now, or nil.
    static var locationProblem: String? {
        let manager = CLLocationManager()
        switch manager.authorizationStatus {
        case .denied, .restricted:
            return "Location is off for Stride. Turn it on in Settings to record your route, distance and pace."
        case .authorizedWhenInUse, .authorizedAlways:
            return manager.accuracyAuthorization == .reducedAccuracy
                ? "Precise Location is off. Stride needs it to measure distance and pace. Turn it on in Settings."
                : nil
        default:
            return nil
        }
    }
}

extension View {
    /// The alert shown when a plan session can't start because of location settings.
    func locationProblemAlert(_ message: Binding<String?>) -> some View {
        modifier(LocationProblemAlert(message: message))
    }
}

private struct LocationProblemAlert: ViewModifier {
    @Binding var message: String?
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content.alert("Can't start the run", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }
}
