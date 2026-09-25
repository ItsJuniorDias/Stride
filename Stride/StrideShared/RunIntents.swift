import AppIntents
import StrideKit

// Compiled into the app and the widget extension: the Live Activity's buttons and the Control
// Center control refer to these intents, and the system runs them in the app.

/// What intents can do to a run. The app registers its run tracker at launch; in the widget
/// extension nothing is registered and the system never runs these intents there.
enum StartRunOutcome {
    case started, alreadyRunning, watchRunning
}

enum ResumeRunOutcome {
    case resumed, alreadyRunning, needsApp, noRun
}

@MainActor
protocol RunIntentHandling: AnyObject {
    /// Starts a free run with the countdown.
    func startRunFromIntent() -> StartRunOutcome
    func pauseRunFromIntent()
    func resumeRunFromIntent() -> ResumeRunOutcome
}

@MainActor
enum RunIntentBridge {
    static weak var handler: (any RunIntentHandling)?
}

nonisolated struct StartRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Run"
    static let description = IntentDescription("Opens Stride and starts a run after a 3-second countdown.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let handler = RunIntentBridge.handler else { return .result(dialog: "Open Stride to start a run.") }
        let dialog: IntentDialog = switch handler.startRunFromIntent() {
        case .started: "Starting your run."
        case .alreadyRunning: "You're already on a run."
        case .watchRunning: "You're already running with Apple Watch."
        }
        return .result(dialog: dialog)
    }
}

nonisolated struct PauseRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Pause Run"
    static let description = IntentDescription("Pauses the run you're recording in Stride.")

    @MainActor
    func perform() async throws -> some IntentResult {
        RunIntentBridge.handler?.pauseRunFromIntent()
        return .result()
    }
}

nonisolated struct ResumeRunIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Resume Run"
    static let description = IntentDescription("Resumes your paused run in Stride.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let dialog: IntentDialog = switch RunIntentBridge.handler?.resumeRunFromIntent() ?? .noRun {
        case .resumed: "Run resumed."
        case .alreadyRunning: "Your run is already going."
        case .needsApp: "Open Stride to resume your run."
        case .noRun: "There's no paused run."
        }
        return .result(dialog: dialog)
    }
}
