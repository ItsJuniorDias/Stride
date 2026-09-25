import Foundation
import SwiftData
import WidgetKit
import StrideKit

/// Keeps the widgets' snapshot current: written to the App Group, sent to Apple Watch for its
/// complications, and the widgets asked to redraw.
@MainActor
enum WidgetSync {
    private static var lastWritten: WidgetSnapshot?

    static func update(from runs: [Run]) {
        let defaults = UserDefaults.standard
        let unit = UnitSystem(rawValue: defaults.string(forKey: StrideSettings.unitSystem) ?? "") ?? .metric
        let goal = defaults.object(forKey: StrideSettings.weeklyGoal) as? Double ?? 20
        var snapshot = WidgetSnapshot(runs: runs.map(\.sample), titles: runs.map(\.title), weeklyGoal: goal, unit: unit)
        snapshot.importedWatchRuns = WatchSync.shared.recentImports
        let friends = FriendsService.shared
        if !friends.friendCodes.isEmpty {
            snapshot.myCode = friends.myCode
            var me = friends.myCard(from: runs.map(\.sample))
            // Without a timestamp, so an unchanged week compares equal and doesn't reload widgets.
            me.updatedAt = nil
            snapshot.friendCards = [me] + friends.friendCards
        }
        // Nothing changed but the time: skip the reload, widgets have a daily budget.
        if var previous = lastWritten {
            previous.updatedAt = snapshot.updatedAt
            if previous == snapshot { return }
        }
        snapshot.updatedAt = .now
        lastWritten = snapshot
        WidgetStore.save(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
        WatchSync.shared.pushSettings(complication: true)
    }

    static func update(in context: ModelContext) {
        let runs = (try? context.fetch(FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDate, order: .reverse)]))) ?? []
        update(from: runs)
    }
}
