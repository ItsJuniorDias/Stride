import Foundation
import SwiftData
import CoreData
import CloudKit
import Security
import StrideKit

/// The database, synced across the runner's devices with their private iCloud database.
enum CloudStore {
    static let containerID = "iCloud.alexandrejunior.Stride"

    /// Whether the database opened with iCloud sync (false without the iCloud entitlement or when
    /// CloudKit couldn't be set up; the runs are then local, as before).
    private(set) static var syncsWithICloud = false

    static let syncedModels: [any PersistentModel.Type] = [Run.self, Shoe.self, Challenge.self]

    static func makeContainer() -> ModelContainer {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-initCloudKitSchema") { initializeCloudKitSchema() }
        #endif
        let schema = Schema(syncedModels + [RunVitals.self])
        // Heart rate, on this device only (App Store guideline 5.1.3(ii): no health data in iCloud).
        let vitals = ModelConfiguration("Vitals", schema: Schema([RunVitals.self]), groupContainer: .none, cloudKitDatabase: .none)
        // Runs, shoes and challenges stay in the app's own container, where they've always been:
        // with the App Group the default configuration would move them to the shared one.
        func runs(_ cloud: ModelConfiguration.CloudKitDatabase) -> ModelConfiguration {
            ModelConfiguration(schema: Schema(syncedModels), groupContainer: .none, cloudKitDatabase: cloud)
        }

        // Before iCloud sees the store: heart rate saved by earlier versions moves out of the runs.
        moveVitalsOutOfRuns(schema: schema, configurations: [runs(.none), vitals])

        do {
            guard !vitalsMoveFailed else { throw CocoaError(.featureUnsupported) }
            let container = try ModelContainer(for: schema, configurations: runs(.private(containerID)), vitals)
            syncsWithICloud = true
            return container
        } catch {
            do {
                return try ModelContainer(for: schema, configurations: runs(.none), vitals)
            } catch {
                fatalError("Could not open the Stride database: \(error)")
            }
        }
    }

    private static let vitalsMovedKey = "vitalsMovedOutOfRuns"

    /// Runs saved before heart rate had its own store kept it in the run (average, zones and in the
    /// route). Moved once, with sync off, so it never reaches iCloud.
    private static func moveVitalsOutOfRuns(schema: Schema, configurations: [ModelConfiguration]) {
        guard !UserDefaults.standard.bool(forKey: vitalsMovedKey) else { return }
        guard let container = try? ModelContainer(for: schema, configurations: configurations) else { return }
        let context = ModelContext(container)
        let runs = (try? context.fetch(FetchDescriptor<Run>())) ?? []
        for run in runs {
            let route = run.route
            let hasRouteHeartRate = route.contains { $0.heartRate != nil }
            guard run.averageHeartRate != nil || run.zoneData != nil || hasRouteHeartRate else { continue }
            let vitals = RunVitals(runID: run.id, averageHeartRate: run.averageHeartRate)
            vitals.zoneData = run.zoneData
            if hasRouteHeartRate {
                let split = RunVitals.split(route)
                vitals.heartRates = split.heartRates
                run.route = split.route
            }
            context.insert(vitals)
            run.averageHeartRate = nil
            run.zoneData = nil
        }
        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: vitalsMovedKey)
        } catch {
            // Tried again next launch; until then this launch opens without iCloud (see below).
            vitalsMoveFailed = true
        }
    }

    /// Set when heart rate couldn't be moved out: the store then opens without iCloud this time.
    private static var vitalsMoveFailed = false

    /// This iPhone's id, created once. Kept in the Keychain on this device only: it survives
    /// reinstalling Stride, and a backup restored onto another iPhone doesn't copy it.
    static var deviceID: String {
        if let id = cachedDeviceID { return id }
        let id = Keychain.string(for: "deviceID")
            ?? UserDefaults.standard.string(forKey: StrideSettings.deviceID)
            ?? UUID().uuidString
        Keychain.set(id, for: "deviceID")
        cachedDeviceID = id
        return id
    }

    private static var cachedDeviceID: String?

    #if DEBUG
    /// Launch with `-initCloudKitSchema` on a device signed in to iCloud (Development environment) to
    /// create every record type and field, so the schema can be deployed to Production in the
    /// CloudKit Console. Uses a scratch store: the real one isn't touched.
    static func initializeCloudKitSchema() {
        guard let model = NSManagedObjectModel.makeManagedObjectModel(for: syncedModels) else { return }
        let url = URL.temporaryDirectory.appending(path: "schema-\(UUID().uuidString).store")
        let description = NSPersistentStoreDescription(url: url)
        description.cloudKitContainerOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: containerID)
        description.shouldAddStoreAsynchronously = false
        let container = NSPersistentCloudKitContainer(name: "StrideSchema", managedObjectModel: model)
        container.persistentStoreDescriptions = [description]
        container.loadPersistentStores { _, _ in }
        do {
            try container.initializeCloudKitSchema()
        } catch {
            print("CloudKit schema: \(error)")
        }
        for store in container.persistentStoreCoordinator.persistentStores {
            try? container.persistentStoreCoordinator.remove(store)
        }
    }
    #endif
}

/// Settings that follow the runner to their other iPhone through iCloud's key-value store: goals,
/// units, the coach, the active plan and friends. Health, the default shoe and this device's id
/// stay per device.
@MainActor
final class SettingsSync {
    static let shared = SettingsSync()

    private let store = NSUbiquitousKeyValueStore.default
    private var observers: [NSObjectProtocol] = []
    /// Set while copying from iCloud, so the copy isn't sent straight back.
    private var isPulling = false

    static let keys = [
        StrideSettings.unitSystem, StrideSettings.userName, StrideSettings.weeklyGoal, StrideSettings.yearlyGoal,
        StrideSettings.weightKg, StrideSettings.maxHeartRate, StrideSettings.voiceCoach, StrideSettings.autoPause,
        StrideSettings.voiceInterval, StrideSettings.voiceIncludePace, StrideSettings.voiceIncludeTime,
        StrideSettings.targetPace, StrideSettings.activePlanID, StrideSettings.completedPlanSessions,
        StrideSettings.shareWithFriends, StrideSettings.friendCode, StrideSettings.friendCodes,
        StrideSettings.blockedCodes, StrideSettings.cheered, StrideSettings.cheerWeekKey,
    ]

    /// Tied to the iCloud account: dropped when a different account signs in, so one person's
    /// friends and code don't move into another's.
    static let accountKeys = [
        StrideSettings.shareWithFriends, StrideSettings.friendCode, StrideSettings.friendCodes,
        StrideSettings.blockedCodes, StrideSettings.cheered, StrideSettings.cheerWeekKey,
    ]

    func start() {
        guard observers.isEmpty else { return }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification, object: store, queue: .main
        ) { note in
            let changed = note.userInfo?[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String]
            let reason = note.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? Int
            MainActor.assumeIsolated {
                if reason == NSUbiquitousKeyValueStoreAccountChange {
                    // Another iCloud account: this device's friends belong to the previous one.
                    SettingsSync.shared.isPulling = true
                    Self.accountKeys.forEach(UserDefaults.standard.removeObject(forKey:))
                    SettingsSync.shared.isPulling = false
                    SettingsSync.shared.pull(nil)
                } else {
                    SettingsSync.shared.pull(changed)
                }
            }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { SettingsSync.shared.push() }
        })
        store.synchronize()
        // A new device takes what's in iCloud; values only this device has go up.
        pull(nil)
        push()
    }

    /// iCloud → this device.
    private func pull(_ keys: [String]?) {
        let defaults = UserDefaults.standard
        isPulling = true
        defer { isPulling = false }
        for key in keys ?? Self.keys where Self.keys.contains(key) {
            guard var value = store.object(forKey: key) else { continue }
            // Plan sessions only ever get completed: keep the ones done on either device.
            if key == StrideSettings.completedPlanSessions, let cloud = value as? String {
                let local = defaults.string(forKey: key) ?? ""
                let merged = Set((cloud + "," + local).split(separator: ",").map(String.init).filter { !$0.isEmpty })
                value = merged.sorted().joined(separator: ",")
            }
            if !Self.equal(defaults.object(forKey: key), value) { defaults.set(value, forKey: key) }
        }
    }

    /// This device → iCloud, for the keys that differ.
    private func push() {
        guard !isPulling else { return }
        let defaults = UserDefaults.standard
        for key in Self.keys {
            guard let value = defaults.object(forKey: key) else { continue }
            if !Self.equal(store.object(forKey: key), value) { store.set(value, forKey: key) }
        }
    }

    private static func equal(_ a: Any?, _ b: Any?) -> Bool {
        switch (a, b) {
        case (nil, nil): true
        case let (a as NSObject, b as NSObject): a.isEqual(b)
        default: false
        }
    }
}

/// A few strings in the Keychain, on this device only.
enum Keychain {
    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Stride",
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func set(_ value: String, for account: String) {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Stride",
            kSecAttrAccount as String: account,
        ]
        let data = Data(value.utf8)
        if SecItemUpdate(base as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var item = base
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

