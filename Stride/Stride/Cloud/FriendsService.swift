import Foundation
import CloudKit
import Observation
import StrideKit

/// Friends and their weekly totals, through CloudKit's public database. Each runner who shares
/// has one "Runner" record named after their friend code; adding a friend is fetching that
/// record, so nothing has to be searchable. Nothing is shared until the runner turns it on.
@MainActor
@Observable
final class FriendsService {
    static let shared = FriendsService()

    enum Account: Equatable {
        case unknown, available, noAccount, restricted, unavailable
    }

    private(set) var account: Account = .unknown
    /// Friends' cards, keyed by code; a friend without one isn't sharing (anymore). Cached on
    /// disk, so widgets and Apple Watch keep showing friends before the first refresh.
    private(set) var cards: [String: RunnerCard] = [:]
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    private(set) var errorMessage: String?
    /// Something the runner should know that isn't an error, e.g. "Your code changed".
    private(set) var notice: String?
    /// A friend code from an invite link, waiting to be confirmed.
    var pendingInvite: PendingInvite?

    struct PendingInvite: Identifiable, Equatable {
        let code: String
        var id: String { code }
    }

    @ObservationIgnored private lazy var database = CKContainer(identifier: CloudStore.containerID).publicCloudDatabase
    @ObservationIgnored private var lastPublished: RunnerCard?
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    /// Saves and deletes of my card, one at a time, in order.
    @ObservationIgnored private var operation: Task<Void, Never>?
    @ObservationIgnored private var latestSamples: [RunSample] = []
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Made-up friends for screenshots: nothing goes to iCloud or into settings.
    @ObservationIgnored private var demo: (codes: [String], sharing: Bool, cheered: [String], blocked: [String])?
    /// A code found to belong to someone else was replaced once; a second failure stops there.
    @ObservationIgnored private var rotatedForPermission = false
    private static let demoCode = "WEHMXS2P"

    static let recordType = "Runner"
    private static let cardsCacheKey = "friendCardsCache"
    /// Codes whose public card still has to be deleted (sharing turned off, or a code changed while
    /// offline). Retried until each is gone.
    private static let cardsToDeleteKey = "friendCardsToDelete"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.cardsCacheKey),
           let cached = try? JSONDecoder().decode([String: RunnerCard].self, from: data) {
            cards = cached
        }
        // Friends, sharing and codes can change from another device (iCloud key-value store).
        observers.append(NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FriendsService.shared.settingsChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { FriendsService.shared.accountChanged() }
        })
    }

    @ObservationIgnored private var knownCodes: [String] = UserDefaults.standard.stringArray(forKey: StrideSettings.friendCodes) ?? []
    @ObservationIgnored private var knownSharing = UserDefaults.standard.bool(forKey: StrideSettings.shareWithFriends)

    private func settingsChanged() {
        guard demo == nil else { return }
        let codes = UserDefaults.standard.stringArray(forKey: StrideSettings.friendCodes) ?? []
        let sharing = UserDefaults.standard.bool(forKey: StrideSettings.shareWithFriends)
        if codes != knownCodes {
            knownCodes = codes
            withMutation(keyPath: \.friendCodes) {}
            // Cards of friends removed elsewhere go; new ones come with the next refresh.
            cards = cards.filter { codes.contains($0.key) }
            saveCache()
        }
        if sharing != knownSharing {
            knownSharing = sharing
            withMutation(keyPath: \.isSharing) {}
            if sharing {
                // Turned on on another device: the card stays, and this device keeps it current.
                removeFromDeletion(myCode)
                lastPublished = nil
                publish(from: latestSamples)
            } else {
                // Turned off on another device: make sure the card is gone.
                addToDeletion(myCode)
            }
        }
    }

    private func accountChanged() {
        lastPublished = nil
        Task {
            await checkAccount()
            if account == .available {
                await refresh()
            } else {
                cards = [:]
                lastRefresh = nil
                saveCache()
            }
        }
    }

    private var cardsToDelete: [String] {
        UserDefaults.standard.stringArray(forKey: Self.cardsToDeleteKey) ?? []
    }

    private func addToDeletion(_ code: String) {
        guard demo == nil, !cardsToDelete.contains(code) else { return }
        UserDefaults.standard.set(cardsToDelete + [code], forKey: Self.cardsToDeleteKey)
    }

    private func removeFromDeletion(_ code: String) {
        UserDefaults.standard.set(cardsToDelete.filter { $0 != code }, forKey: Self.cardsToDeleteKey)
    }

    // MARK: Settings

    var isSharing: Bool {
        get {
            access(keyPath: \.isSharing)
            return demo?.sharing ?? UserDefaults.standard.bool(forKey: StrideSettings.shareWithFriends)
        }
        set {
            withMutation(keyPath: \.isSharing) {
                if demo != nil { demo?.sharing = newValue; return }
                knownSharing = newValue
                UserDefaults.standard.set(newValue, forKey: StrideSettings.shareWithFriends)
            }
        }
    }

    /// This runner's code, created the first time it's needed (and synced to their other devices).
    var myCode: String {
        if demo != nil { return Self.demoCode }
        if let code = UserDefaults.standard.string(forKey: StrideSettings.friendCode), ShareCode.normalize(code) != nil { return code }
        let code = ShareCode.generate()
        UserDefaults.standard.set(code, forKey: StrideSettings.friendCode)
        return code
    }

    var friendCodes: [String] {
        get {
            access(keyPath: \.friendCodes)
            return demo?.codes ?? UserDefaults.standard.stringArray(forKey: StrideSettings.friendCodes) ?? []
        }
        set {
            withMutation(keyPath: \.friendCodes) {
                if demo != nil { demo?.codes = newValue; return }
                knownCodes = newValue
                UserDefaults.standard.set(newValue, forKey: StrideSettings.friendCodes)
            }
        }
    }

    var blockedCodes: [String] {
        get {
            access(keyPath: \.blockedCodes)
            return demo?.blocked ?? UserDefaults.standard.stringArray(forKey: StrideSettings.blockedCodes) ?? []
        }
        set {
            withMutation(keyPath: \.blockedCodes) {
                if demo != nil { demo?.blocked = newValue; return }
                UserDefaults.standard.set(newValue, forKey: StrideSettings.blockedCodes)
            }
        }
    }

    /// Friends' cards in the order they were added.
    var friendCards: [RunnerCard] {
        friendCodes.compactMap { cards[$0] }
    }

    /// Friends whose card couldn't be found: not sharing, or not anymore.
    var silentFriends: [String] {
        guard lastRefresh != nil else { return [] }
        return friendCodes.filter { cards[$0] == nil }
    }

    /// The name friends see: the runner's name, tidied, or "Runner". Links and handles are left
    /// out, so a name can't carry them.
    static func publicName(_ raw: String) -> String {
        let words = raw.split(whereSeparator: \.isWhitespace).filter { word in
            let lower = word.lowercased()
            let digits = lower.filter(\.isNumber).count
            // No links, handles, domains or phone numbers.
            return !(lower.contains("http") || lower.contains("/") || lower.contains("@") || digits >= 5
                || lower.range(of: #"\.[a-z]{2,}"#, options: .regularExpression) != nil)
        }
        let name = String(words.joined(separator: " ").prefix(30))
        return name.isEmpty ? "Runner" : name
    }

    private var displayName: String {
        Self.publicName(UserDefaults.standard.string(forKey: StrideSettings.userName) ?? "")
    }

    // MARK: Account

    func checkAccount() async {
        guard demo == nil else { return }
        do {
            account = switch try await CKContainer(identifier: CloudStore.containerID).accountStatus() {
            case .available: .available
            case .noAccount: .noAccount
            case .restricted: .restricted
            default: .unavailable
            }
        } catch {
            account = .unavailable
        }
    }

    // MARK: My card

    /// My card as friends would see it now. The friends I cheered appear as tokens only they can read.
    func myCard(from samples: [RunSample], now: Date = .now) -> RunnerCard {
        let week = RunnerStats.weekKey(for: now)
        let code = myCode
        let cheered = cheeredThisWeek(week).map { CheerToken.make(for: $0, from: code) }
        return RunnerCard(code: code, name: displayName, stats: RunnerStats.compute(from: samples, now: now),
                          cheered: cheered, cheerWeekKey: week, updatedAt: now)
    }

    private func cheeredThisWeek(_ week: String) -> [String] {
        if let demo { return demo.cheered }
        let defaults = UserDefaults.standard
        return defaults.string(forKey: StrideSettings.cheerWeekKey) == week ? defaults.stringArray(forKey: StrideSettings.cheered) ?? [] : []
    }

    /// Publishes my card when sharing is on and something changed (runs, name, cheers, a new week).
    /// Coalesced: calls in quick succession publish once, with what's current by then.
    func publish(from samples: [RunSample]) {
        latestSamples = samples
        guard isSharing, demo == nil else { return }
        publishTask?.cancel()
        publishTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, isSharing else { return }
            let card = myCard(from: latestSamples)
            guard !Self.sameContent(card, lastPublished) else { return }
            enqueue { await self.save(card) }
        }
    }

    /// Runs `work` after every save or delete already queued.
    private func enqueue(_ work: @escaping @MainActor () async -> Void) {
        let previous = operation
        operation = Task {
            await previous?.value
            await work()
        }
    }

    private func save(_ card: RunnerCard) async {
        // Turned off while this was waiting: don't bring the card back.
        guard isSharing, demo == nil, card.code == myCode else { return }
        let id = Self.recordID(for: card.code)
        let record = CKRecord(recordType: Self.recordType, recordID: id)
        Self.fill(record, with: card)
        do {
            let (results, _) = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
            if case .failure(let error) = results[id] { throw error }
            lastPublished = card
            rotatedForPermission = false
            errorMessage = nil
        } catch let error as CKError where error.code == .permissionFailure {
            // Someone else's record has this name (they took the code first): use a new code, once.
            guard !rotatedForPermission else {
                errorMessage = "Couldn't share your card. Try again later."
                return
            }
            rotatedForPermission = true
            UserDefaults.standard.removeObject(forKey: StrideSettings.friendCode)
            lastPublished = nil
            notice = "Your friend code changed to \(ShareCode.display(myCode)). Send your friends the new one."
            publish(from: latestSamples)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// Turns sharing on (publishing now) or off (deleting my card, so friends stop seeing it; retried
    /// until it's gone).
    func setSharing(_ on: Bool, samples: [RunSample]) {
        isSharing = on
        latestSamples = samples
        publishTask?.cancel()
        lastPublished = nil
        guard demo == nil else { return }
        let code = myCode
        if on {
            removeFromDeletion(code)
            publish(from: samples)
        } else {
            addToDeletion(code)
            enqueue { await self.deleteCard(code) }
        }
    }

    /// Tries again to delete cards that couldn't be deleted (offline when sharing was turned off or
    /// the code changed).
    func retryPendingDeletion() {
        guard demo == nil else { return }
        for code in cardsToDelete {
            enqueue { await self.deleteCard(code) }
        }
    }

    private func deleteCard(_ code: String) async {
        // The live card (sharing is on again, maybe from another device) stays.
        guard demo == nil, !(isSharing && code == myCode) else {
            removeFromDeletion(code)
            return
        }
        do {
            _ = try await database.deleteRecord(withID: Self.recordID(for: code))
            removeFromDeletion(code)
        } catch let error as CKError where error.code == .unknownItem {
            removeFromDeletion(code)
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    /// A new code: whoever had the old one stops seeing me. The old card is deleted (retried until
    /// it's gone).
    func changeCode(samples: [RunSample]) {
        guard demo == nil else { return }
        let old = myCode
        UserDefaults.standard.set(ShareCode.generate(), forKey: StrideSettings.friendCode)
        lastPublished = nil
        addToDeletion(old)
        enqueue { await self.deleteCard(old) }
        if isSharing { publish(from: samples) }
        notice = "Your new code is \(ShareCode.display(myCode)). Friends who had the old one no longer see you."
    }

    // MARK: Friends

    /// Fetches every friend's card.
    func refresh() async {
        let codes = friendCodes
        guard !codes.isEmpty, !isRefreshing, demo == nil else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            let results = try await database.records(for: codes.map(Self.recordID(for:)))
            var fetched: [String: RunnerCard] = [:]
            for (id, result) in results {
                guard case .success(let record) = result, let card = Self.card(from: record) else { continue }
                fetched[Self.code(from: id)] = card
            }
            // Friends added or removed while this was loading stay as they are now.
            let current = friendCodes
            cards = fetched.filter { current.contains($0.key) }.merging(cards.filter { current.contains($0.key) && !codes.contains($0.key) }) { new, _ in new }
            saveCache()
            lastRefresh = .now
            errorMessage = nil
        } catch {
            errorMessage = Self.message(for: error)
        }
    }

    private func saveCache() {
        guard demo == nil else { return }
        UserDefaults.standard.set(try? JSONEncoder().encode(cards), forKey: Self.cardsCacheKey)
    }

    enum AddError: LocalizedError {
        case invalid, yourself, notFound, already, blocked, failed(String)

        var errorDescription: String? {
            switch self {
            case .invalid: "That doesn't look like a friend code. It has 8 letters and numbers, like ABCD-EFGH."
            case .yourself: "That's your own code."
            case .notFound: "No one is sharing with that code. Ask your friend to turn on sharing in Stride."
            case .already: "You're already friends."
            case .blocked: "You blocked this runner."
            case .failed(let message): message
            }
        }
    }

    /// Adds a friend by code, after checking they share a card.
    func addFriend(_ input: String) async throws(AddError) {
        guard let code = ShareCode.normalize(input) else { throw .invalid }
        guard code != myCode else { throw .yourself }
        guard !friendCodes.contains(code) else { throw .already }
        guard !blockedCodes.contains(code) else { throw .blocked }
        let record: CKRecord
        do {
            record = try await database.record(for: Self.recordID(for: code))
        } catch let error as CKError where error.code == .unknownItem {
            throw .notFound
        } catch {
            throw .failed(Self.message(for: error))
        }
        friendCodes.append(code)
        if let card = Self.card(from: record) {
            cards[code] = card
            saveCache()
        }
    }

    func removeFriend(_ code: String) {
        friendCodes.removeAll { $0 == code }
        cards[code] = nil
        saveCache()
        // A cheer for them this week comes off my card too.
        let week = RunnerStats.weekKey(for: .now)
        var cheered = cheeredThisWeek(week)
        if cheered.contains(code) {
            cheered.removeAll { $0 == code }
            if demo != nil {
                demo?.cheered = cheered
            } else {
                UserDefaults.standard.set(cheered, forKey: StrideSettings.cheered)
            }
            publish(from: latestSamples)
        }
    }

    /// Removes a friend and won't add them again. They keep seeing me until I change my code.
    func block(_ code: String) {
        removeFriend(code)
        if !blockedCodes.contains(code) { blockedCodes.append(code) }
    }

    /// Cheers a friend this week, or takes the cheer back. It shows on my card, which they see.
    func toggleCheer(_ code: String, samples: [RunSample]) {
        let week = RunnerStats.weekKey(for: .now)
        var cheered = cheeredThisWeek(week)
        if let index = cheered.firstIndex(of: code) { cheered.remove(at: index) } else { cheered.append(code) }
        if demo != nil {
            demo?.cheered = cheered
        } else {
            UserDefaults.standard.set(cheered, forKey: StrideSettings.cheered)
            UserDefaults.standard.set(week, forKey: StrideSettings.cheerWeekKey)
        }
        withMutation(keyPath: \.cards) {}
        publish(from: samples)
    }

    func hasCheered(_ code: String) -> Bool {
        access(keyPath: \.cards)
        return cheeredThisWeek(RunnerStats.weekKey(for: .now)).contains(code)
    }

    // MARK: Records

    static func recordID(for code: String) -> CKRecord.ID {
        CKRecord.ID(recordName: "runner-\(code)")
    }

    static func code(from id: CKRecord.ID) -> String {
        String(id.recordName.dropFirst("runner-".count))
    }

    static func fill(_ record: CKRecord, with card: RunnerCard) {
        let stats = card.stats
        record["name"] = publicName(card.name)
        record["weekKey"] = stats.weekKey
        record["weekDistance"] = stats.weekDistance
        record["weekRuns"] = stats.weekRuns
        record["weekDuration"] = stats.weekDuration
        record["monthKey"] = stats.monthKey
        record["monthDistance"] = stats.monthDistance
        record["monthRuns"] = stats.monthRuns
        record["streakWeeks"] = stats.streakWeeks
        record["lastRunDate"] = stats.lastRunDate
        record["lastRunDistance"] = stats.lastRunDistance
        record["lastRunDuration"] = stats.lastRunDuration
        record["cheered"] = card.cheered.isEmpty ? nil : card.cheered
        record["cheerWeekKey"] = card.cheerWeekKey
    }

    static func card(from record: CKRecord) -> RunnerCard? {
        guard let name = record["name"] as? String, let weekKey = record["weekKey"] as? String,
              let monthKey = record["monthKey"] as? String
        else { return nil }
        let stats = RunnerStats(
            weekKey: weekKey,
            weekDistance: record["weekDistance"] as? Double ?? 0,
            weekRuns: record["weekRuns"] as? Int ?? 0,
            weekDuration: record["weekDuration"] as? Double ?? 0,
            monthKey: monthKey,
            monthDistance: record["monthDistance"] as? Double ?? 0,
            monthRuns: record["monthRuns"] as? Int ?? 0,
            streakWeeks: record["streakWeeks"] as? Int ?? 0,
            lastRunDate: record["lastRunDate"] as? Date,
            lastRunDistance: record["lastRunDistance"] as? Double,
            lastRunDuration: record["lastRunDuration"] as? Double
        )
        // No timestamp: it changes on every save, and cards that only differ by it would redraw
        // widgets and use up Apple Watch transfers for nothing.
        return RunnerCard(code: code(from: record.recordID), name: publicName(name), stats: stats,
                          cheered: record["cheered"] as? [String] ?? [], cheerWeekKey: record["cheerWeekKey"] as? String ?? "")
    }

    /// Same content, ignoring when it was made.
    private static func sameContent(_ a: RunnerCard, _ b: RunnerCard?) -> Bool {
        guard var b else { return false }
        b.updatedAt = a.updatedAt
        return a == b
    }

    private static func message(for error: Error) -> String {
        guard let error = error as? CKError else { return "Something went wrong. Try again." }
        return switch error.code {
        case .notAuthenticated: "Sign in to iCloud in Settings to use friends."
        case .networkUnavailable, .networkFailure: "You're offline. Friends update when you're back online."
        case .serviceUnavailable, .requestRateLimited, .zoneBusy: "iCloud is busy. Try again in a moment."
        case .quotaExceeded: "Your iCloud storage is full."
        default: "Couldn't reach iCloud. Try again."
        }
    }

    #if DEBUG
    /// Launch with `-demoFriends` to fill the leaderboard with made-up friends, for screenshots.
    /// Kept in memory: nothing is written to settings or iCloud.
    func loadDemo() {
        let week = RunnerStats.weekKey(for: .now)
        let month = RunnerStats.monthKey(for: .now)
        let people: [(String, String, Double, Int, Double, Bool)] = [
            ("ANAK7Q2M", "Ana Souza", 28_400, 4, 96_000, true), ("BRUN8X4P", "Bruno Lima", 19_900, 3, 71_000, false),
            ("CARL3V9T", "Carla Mendes", 12_300, 2, 55_000, true), ("DIEG6H2W", "Diego Alves", 0, 0, 20_000, false),
        ]
        demo = (people.map(\.0), true, [], [])
        publishTask?.cancel()
        errorMessage = nil
        let me = myCode
        cards = Dictionary(uniqueKeysWithValues: people.map { code, name, km, runs, monthKm, cheered in
            (code, RunnerCard(code: code, name: name,
                              stats: RunnerStats(weekKey: km > 0 ? week : "2026-W01", weekDistance: km, weekRuns: runs,
                                                 monthKey: month, monthDistance: monthKm, monthRuns: runs + 6, streakWeeks: runs > 0 ? runs + 2 : 0,
                                                 lastRunDate: .now.addingTimeInterval(-Double(runs + 1) * 36_000), lastRunDistance: 8_000,
                                                 lastRunDuration: 2_700),
                              cheered: cheered ? [CheerToken.make(for: me, from: code)] : [], cheerWeekKey: week))
        })
        withMutation(keyPath: \.friendCodes) {}
        withMutation(keyPath: \.isSharing) {}
        account = .available
        lastRefresh = .now
    }

    /// Launch with `-initCloudKitSchema` (on a device signed in to iCloud, Development environment)
    /// to create every Runner field, so the schema can be deployed to Production.
    func initializeSchema() async {
        let code = "SCHEMA22"
        let record = CKRecord(recordType: Self.recordType, recordID: Self.recordID(for: code))
        Self.fill(record, with: RunnerCard(
            code: code, name: "Schema",
            stats: RunnerStats(weekKey: "2026-W01", weekDistance: 1, weekRuns: 1, weekDuration: 1, monthKey: "2026-01",
                               monthDistance: 1, monthRuns: 1, streakWeeks: 1, lastRunDate: .now, lastRunDistance: 1, lastRunDuration: 1),
            cheered: ["0000000000000000"], cheerWeekKey: "2026-W01"))
        _ = try? await database.modifyRecords(saving: [record], deleting: [], savePolicy: .allKeys)
        _ = try? await database.deleteRecord(withID: record.recordID)
    }
    #endif
}
