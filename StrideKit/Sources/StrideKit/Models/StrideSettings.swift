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
    /// The week the active plan restarted from after a break (``PlanRepeat/rawValue``), empty for none.
    /// Not synced: it never changes what's marked done, so each device can go its own way.
    public static let planRepeat = "planRepeat"
    /// The last run's date (seconds since 1970) when "Not now" hid the suggestion to restart from an
    /// earlier week, so it stays hidden until the next break. Not synced.
    public static let planRepeatDismissed = "planRepeatDismissed"
    /// The shoe new runs use (iPhone, Watch and manual), as a UUID string; empty for none.
    public static let defaultShoeID = "defaultShoeID"
    /// The Progress tab's period: week, month, year or all.
    public static let statsPeriod = "statsPeriod"
    /// Save runs recorded on iPhone and added by hand to Apple Health.
    public static let healthSave = "healthSave"
    /// Runs from this moment on are saved to Health (a Date); earlier ones only when asked.
    public static let healthSaveSince = "healthSaveSince"
    /// Share this week's and month's running with friends (public CloudKit card).
    public static let shareWithFriends = "shareWithFriends"
    /// This runner's friend code.
    public static let friendCode = "friendCode"
    /// Friends' codes, in the order they were added.
    public static let friendCodes = "friendCodes"
    /// Codes this runner blocked: removed and can't be added again.
    public static let blockedCodes = "blockedCodes"
    /// Friends cheered this week, and the ISO week it's for.
    public static let cheered = "cheered"
    public static let cheerWeekKey = "cheerWeekKey"
    /// A random id for this install, so runs remember which device recorded them.
    public static let deviceID = "deviceID"
    /// The welcome pages were finished on this device. Not synced: each device shows them once.
    public static let hasOnboarded = "hasOnboarded"
    /// Stride Pro as last confirmed by the App Store on this device, so locks don't flicker at launch.
    /// Not synced: Pro belongs to the Apple Account, not the iCloud one.
    public static let proLastKnown = "proLastKnown"

    /// Reads a Bool setting that defaults to true when never set.
    public static func bool(_ key: String, default value: Bool = true) -> Bool {
        UserDefaults.standard.object(forKey: key) as? Bool ?? value
    }
}
