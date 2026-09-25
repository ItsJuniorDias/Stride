import Foundation
import StrideKit

/// Which training-plan sessions are done, kept in UserDefaults as a comma-separated list.
enum PlanProgress {
    static func completed(from raw: String) -> Set<String> {
        Set(raw.split(separator: ",").map(String.init))
    }

    static var completed: Set<String> {
        completed(from: UserDefaults.standard.string(forKey: StrideSettings.completedPlanSessions) ?? "")
    }

    static func markCompleted(_ id: String) {
        set(id, done: true)
    }

    static func set(_ id: String, done: Bool) {
        var sessions = completed
        if done { sessions.insert(id) } else { sessions.remove(id) }
        UserDefaults.standard.set(sessions.sorted().joined(separator: ","), forKey: StrideSettings.completedPlanSessions)
    }
}
