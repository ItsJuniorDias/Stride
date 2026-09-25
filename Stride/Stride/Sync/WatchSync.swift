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

    /// Sends the settings the Watch needs. The latest context replaces any earlier one.
    func pushSettings() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              WCSession.default.isPaired, WCSession.default.isWatchAppInstalled
        else { return }
        let defaults = UserDefaults.standard
        let context: [String: Any] = [
            StrideSettings.unitSystem: defaults.string(forKey: StrideSettings.unitSystem) ?? UnitSystem.metric.rawValue,
            StrideSettings.maxHeartRate: defaults.double(forKey: StrideSettings.maxHeartRate),
        ]
        try? WCSession.default.updateApplicationContext(context)
    }

    private static let importedIDsKey = "importedWatchRunIDs"

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
            context.insert(Run(transfer: transfer))
            do {
                try context.save()
            } catch {
                return
            }
        }
        importedIDs.insert(key)
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.pushSettings() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Pairing or the Watch app's install state changed: push settings to the (new) Watch app.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.pushSettings() }
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
