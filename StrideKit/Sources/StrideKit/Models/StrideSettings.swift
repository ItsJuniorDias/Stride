import Foundation

/// UserDefaults keys shared by the app and its settings screens.
public enum StrideSettings {
    public static let unitSystem = "unitSystem"
    public static let userName = "userName"
    /// Weekly distance goal, in the runner's display unit.
    public static let weeklyGoal = "weeklyGoal"
    /// Yearly distance goal, in the runner's display unit.
    public static let yearlyGoal = "yearlyGoal"
    public static let weightKg = "weightKg"
    public static let maxHeartRate = "maxHeartRate"
    public static let voiceCoach = "voiceCoach"
    public static let autoPause = "autoPause"
    public static let didSeedSampleData = "didSeedSampleData"
    /// Voice announcements every this many units (km or mi): 0.5, 1, 2 or 5.
    public static let voiceInterval = "voiceInterval"
    public static let voiceIncludePace = "voiceIncludePace"
    public static let voiceIncludeTime = "voiceIncludeTime"
    /// Target pace in seconds per kilometer, 0 when off.
    public static let targetPace = "targetPace"
    public static let activePlanID = "activePlanID"
    /// Completed training-plan session ids, comma separated.
    public static let completedPlanSessions = "completedPlanSessions"

    /// Reads a Bool setting that defaults to true when never set.
    public static func bool(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}
