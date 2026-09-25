import AppIntents
import SwiftData
import SwiftUI
import StrideKit
import StrideUI

/// The database, for intents Siri runs without opening the app.
@MainActor
enum IntentStore {
    static var context: ModelContext { StrideApp.sharedContainer.mainContext }

    static var unit: UnitSystem {
        UnitSystem(rawValue: UserDefaults.standard.string(forKey: StrideSettings.unitSystem) ?? "") ?? .metric
    }

    static func snapshot() -> WidgetSnapshot {
        let runs = (try? context.fetch(FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDate, order: .reverse)]))) ?? []
        let goal = UserDefaults.standard.object(forKey: StrideSettings.weeklyGoal) as? Double ?? 20
        return WidgetSnapshot(runs: runs.map(\.sample), titles: runs.map(\.title), weeklyGoal: goal, unit: unit)
    }
}

nonisolated struct FinishRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Finish Run"
    static let description = IntentDescription("Finishes and saves the run you're recording in Stride.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let tracker = RunIntentBridge.handler as? RunTracker else { return .result(dialog: "There's no run to finish.") }
        tracker.restoreIfNeeded()
        guard tracker.phase == .running || tracker.phase == .paused else { return .result(dialog: "There's no run to finish.") }
        tracker.finish(in: IntentStore.context)
        return .result(dialog: "Run saved. Nice work.")
    }
}

nonisolated struct WeeklySummaryIntent: AppIntent {
    static let title: LocalizedStringResource = "This Week's Running"
    static let description = IntentDescription("How far you've run this week, against your weekly goal.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let snapshot = IntentStore.snapshot()
        let unit = snapshot.unit
        let week = snapshot.week(containing: .now)
        let goalMeters = snapshot.weeklyGoal * unit.metersPerUnit
        var sentence: String
        if week.runs == 0 {
            sentence = "No runs yet this week."
        } else {
            sentence = "You've run \(CoachScript.spokenDistance(week.distance, unit: unit)) in \(week.runs) \(week.runs == 1 ? "run" : "runs") this week."
        }
        if goalMeters > 0 {
            sentence += week.distance >= goalMeters
                ? " Weekly goal reached."
                : " \(CoachScript.spokenDistance(goalMeters - week.distance, unit: unit)) to go to your goal."
        }
        return .result(dialog: IntentDialog(stringLiteral: sentence)) {
            WeekSnippetView(snapshot: snapshot)
        }
    }
}

nonisolated struct LastRunIntent: AppIntent {
    static let title: LocalizedStringResource = "Last Run"
    static let description = IntentDescription("Your most recent run's distance, time and pace.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var descriptor = FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDate, order: .reverse)])
        descriptor.fetchLimit = 1
        guard let run = try? IntentStore.context.fetch(descriptor).first else {
            return .result(dialog: "You haven't recorded a run yet.")
        }
        let unit = IntentStore.unit
        var sentence = "\(run.title), \(run.startDate.formatted(.relative(presentation: .named))): "
        sentence += "\(CoachScript.spokenDistance(run.distance, unit: unit)) in \(CoachScript.spokenDuration(run.duration))"
        if let pace = run.averagePace(in: unit) {
            sentence += ", at \(CoachScript.spokenPace(pace, unit: unit))"
        }
        return .result(dialog: IntentDialog(stringLiteral: sentence + "."))
    }
}

nonisolated struct StrideShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartRunIntent(), phrases: [
            "Start a run in \(.applicationName)",
            "Start running with \(.applicationName)",
            "Start a \(.applicationName) run",
        ], shortTitle: "Start Run", systemImageName: "figure.run")
        AppShortcut(intent: PauseRunIntent(), phrases: [
            "Pause my \(.applicationName) run",
            "Pause \(.applicationName)",
        ], shortTitle: "Pause Run", systemImageName: "pause.fill")
        AppShortcut(intent: ResumeRunIntent(), phrases: [
            "Resume my \(.applicationName) run",
            "Resume \(.applicationName)",
        ], shortTitle: "Resume Run", systemImageName: "play.fill")
        AppShortcut(intent: FinishRunIntent(), phrases: [
            "Finish my \(.applicationName) run",
            "End my \(.applicationName) run",
        ], shortTitle: "Finish Run", systemImageName: "stop.fill")
        AppShortcut(intent: WeeklySummaryIntent(), phrases: [
            "How far have I run this week in \(.applicationName)",
            "My week in \(.applicationName)",
            "\(.applicationName) weekly summary",
        ], shortTitle: "This Week", systemImageName: "chart.bar.fill")
        AppShortcut(intent: LastRunIntent(), phrases: [
            "Show my last \(.applicationName) run",
            "My last run in \(.applicationName)",
        ], shortTitle: "Last Run", systemImageName: "clock.arrow.circlepath")
    }
}

/// Siri's card for the weekly summary: distance against the goal and a bar per day.
struct WeekSnippetView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        let unit = snapshot.unit
        let week = snapshot.week(containing: .now)
        let days = snapshot.days(ofWeekContaining: .now)
        let peak = max(days.max() ?? 0, 1)
        let goal = snapshot.weeklyGoal
        let done = week.distance / unit.metersPerUnit
        HStack(spacing: Space.x4) {
            ProgressRing(progress: goal > 0 ? done / goal : 0, lineWidth: 8) {
                VStack(spacing: 0) {
                    Text(done.formatted(.number.precision(.fractionLength(1))))
                        .font(.headline.width(.expanded))
                        .monospacedDigit()
                    Text("of \(Int(goal)) \(unit.distanceSymbol)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(width: 84, height: 84)
            VStack(alignment: .leading, spacing: Space.x2) {
                Text("\(week.runs) \(week.runs == 1 ? "run" : "runs") · \(RunFormat.duration(week.duration))")
                    .font(.subheadline.weight(.semibold))
                HStack(alignment: .bottom, spacing: 4) {
                    ForEach(Array(days.enumerated()), id: \.offset) { _, meters in
                        Capsule()
                            .fill(meters > 0 ? Color.track : Color.secondary.opacity(0.25))
                            .frame(width: 10, height: max(6, 44 * meters / peak))
                    }
                }
                .frame(height: 44, alignment: .bottom)
            }
            Spacer(minLength: 0)
        }
        .padding()
    }
}
