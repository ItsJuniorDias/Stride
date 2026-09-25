import Foundation
import WatchConnectivity
import WidgetKit
import WatchKit
import StrideKit

/// Sends finished runs to the iPhone app. Every run is written to an outbox on disk first and only
/// removed once delivered, so a run survives iPhone being out of range or the app being terminated.
final class WatchConnector: NSObject {
    static let shared = WatchConnector()

    private var outbox: URL {
        URL.documentsDirectory.appending(path: "Outbox", directoryHint: .isDirectory)
    }

    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ transfer: RunTransfer) {
        do {
            try FileManager.default.createDirectory(at: outbox, withIntermediateDirectories: true)
            let file = outbox.appending(path: "\(transfer.id.uuidString).json")
            try JSONEncoder().encode(transfer).write(to: file, options: .atomic)
        } catch {
            return
        }
        if WCSession.default.activationState == .activated {
            flushOutbox()
        } else {
            activate()
        }
    }

    /// Queues anything still in the outbox, e.g. when the app becomes active.
    func retryPending() {
        guard WCSession.default.activationState == .activated else { return }
        flushOutbox()
    }

    /// Queues every outbox file that isn't already being transferred.
    private func flushOutbox() {
        let session = WCSession.default
        let inFlight = Set(session.outstandingFileTransfers.map(\.file.fileURL.lastPathComponent))
        let files = (try? FileManager.default.contentsOfDirectory(at: outbox, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.pathExtension == "json" && !inFlight.contains(file.lastPathComponent) {
            session.transferFile(file, metadata: ["kind": "run"])
        }
    }
}

extension WatchConnector: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        guard activationState == .activated else { return }
        Task { @MainActor in self.flushOutbox() }
    }

    /// Settings pushed from iPhone (units, max heart rate).
    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let unit = applicationContext[StrideSettings.unitSystem] as? String
        let maxHeartRate = applicationContext[StrideSettings.maxHeartRate] as? Double
        let snapshot = (applicationContext[WidgetStore.contextKey] as? Data).flatMap(WidgetStore.decode)
        Task { @MainActor in
            if let unit { UserDefaults.standard.set(unit, forKey: StrideSettings.unitSystem) }
            if let maxHeartRate, maxHeartRate > 0 { UserDefaults.standard.set(maxHeartRate, forKey: StrideSettings.maxHeartRate) }
            if let snapshot { self.received(snapshot) }
        }
    }

    /// A complication transfer from iPhone: the week's snapshot.
    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let snapshot = (userInfo[WidgetStore.contextKey] as? Data).flatMap(WidgetStore.decode)
        Task { @MainActor in
            if let snapshot { self.received(snapshot) }
        }
    }

    nonisolated func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        if let error {
            // Permanent failures wait for the next launch; anything else is retried in a minute.
            if let code = (error as? WCError)?.code,
               [.companionAppNotInstalled, .watchAppNotInstalled, .fileAccessDenied].contains(code) { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(60))
                self.retryPending()
            }
            return
        }
        Task { @MainActor in
            // Delivered: drop any duplicate still queued for the same run, then the outbox copy.
            WCSession.default.outstandingFileTransfers
                .filter { $0.file.fileURL.lastPathComponent == url.lastPathComponent }
                .forEach { $0.cancel() }
            try? FileManager.default.removeItem(at: url)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        guard session.isReachable else { return }
        Task { @MainActor in self.retryPending() }
    }
}

extension WatchConnector {
    private func received(_ snapshot: WidgetSnapshot) {
        WidgetStore.saveFromPhone(snapshot)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// watchOS woke the app in the background for data from iPhone. The task is completed once
    /// everything pending has been delivered (or after 15 seconds), so the snapshot lands first.
    func handle(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        activate()
        Task { @MainActor in
            let deadline = Date.now.addingTimeInterval(15)
            // hasContentPending only means something once the session is active.
            while WCSession.default.activationState != .activated || WCSession.default.hasContentPending, Date.now < deadline {
                try? await Task.sleep(for: .milliseconds(300))
            }
            // Let the delegate's hop to the main actor save the snapshot first.
            try? await Task.sleep(for: .milliseconds(300))
            task.setTaskCompletedWithSnapshot(false)
        }
    }
}
