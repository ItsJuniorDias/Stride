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
}
