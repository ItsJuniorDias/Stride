import Foundation
import SwiftData
import WatchConnectivity
import StrideKit

/// Receives runs recorded on Apple Watch and saves them, and keeps the Watch's settings
/// (units, max heart rate) in step with iPhone.
final class WatchSync: NSObject {
    static let shared = WatchSync()

    private var container: ModelContainer?

    func activate(container: ModelContainer) {
        self.container = container
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Sends the settings the Watch needs. The latest context replaces any earlier one. With
    /// `complication`, the week's snapshot also goes as a complication transfer, which wakes the
    /// Watch app to redraw a complication on the face (about 50 a day).
    func pushSettings(complication: Bool = false) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled
        else { return }
        let defaults = UserDefaults.standard
        var context: [String: Any] = [
            StrideSettings.unitSystem: defaults.string(forKey: StrideSettings.unitSystem) ?? UnitSystem.metric.rawValue,
            StrideSettings.maxHeartRate: defaults.double(forKey: StrideSettings.maxHeartRate),
        ]
        // The week so far, for the Watch's complications.
        let snapshotData = WidgetStore.load().flatMap(WidgetStore.encoded)
        if let snapshotData { context[WidgetStore.contextKey] = snapshotData }
        try? WCSession.default.updateApplicationContext(context)
        if complication, let snapshotData, WCSession.default.isComplicationEnabled,
           WCSession.default.remainingComplicationUserInfoTransfers > 0 {
            WCSession.default.transferCurrentComplicationUserInfo([WidgetStore.contextKey: snapshotData])
        }
    }

    private static let importedIDsKey = "importedWatchRunIDs"
    private static let recentImportsKey = "importedWatchRunDates"

    /// Start dates of the last Watch runs imported, sent back so the Watch stops counting them itself.
    var recentImports: [Date] {
        get { UserDefaults.standard.array(forKey: Self.recentImportsKey) as? [Date] ?? [] }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.recentImportsKey) }
    }

    /// Ids of every Watch run already imported. Kept even after the run is deleted, so a re-sent
    /// file can't bring back a run the runner removed.
    private var importedIDs: Set<String> {
        get { Set(UserDefaults.standard.stringArray(forKey: Self.importedIDsKey) ?? []) }
        set { UserDefaults.standard.set(Array(newValue), forKey: Self.importedIDsKey) }
    }

    /// Inserts a run sent by the Watch, once.
    func importRun(from data: Data) {
        guard let container, let transfer = try? JSONDecoder().decode(RunTransfer.self, from: data),
              transfer.duration > 0
        else { return }
        let key = transfer.id.uuidString
        guard !importedIDs.contains(key) else { return }

        let context = container.mainContext
        let id = transfer.id
        let existing = (try? context.fetchCount(FetchDescriptor<Run>(predicate: #Predicate { $0.id == id }))) ?? 0
        if existing == 0 {
            let run = Run(transfer: transfer)
            run.shoe = ShoeDefaults.shoe(in: context)
            run.originDevice = CloudStore.deviceID
            context.insert(run)
            // Heart rate stays on this iPhone (never in iCloud).
            let vitals = RunVitals(transfer: transfer)
            if !vitals.isEmpty { context.insert(vitals) }
            do {
                try context.save()
            } catch {
                return
            }
        }
        importedIDs.insert(key)
        recentImports = (recentImports + [transfer.startDate]).suffix(30)
        MirroredWorkout.shared.watchRunImported(startDate: transfer.startDate)
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in
            MirroredWorkout.shared.updateWatchAvailability()
            if activationState == .activated { self.pushSettings() }
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {
        Task { @MainActor in MirroredWorkout.shared.updateWatchAvailability() }
    }

    /// Pairing or the Watch app's install state changed: push settings to the (new) Watch app.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            MirroredWorkout.shared.updateWatchAvailability()
            self.pushSettings()
        }
    }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Switching to another Watch: reactivate for the new one.
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceive file: WCSessionFile) {
        // The file is deleted when this method returns, so read it now.
        guard let data = try? Data(contentsOf: file.fileURL) else { return }
        Task { @MainActor in self.importRun(from: data) }
    }
}
