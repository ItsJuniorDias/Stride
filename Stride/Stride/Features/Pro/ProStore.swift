import Foundation
import Observation
import StoreKit
import StrideKit

/// Stride Pro: the two subscriptions, whether this Apple Account has Pro (its own, a free trial, a
/// billing grace period or Family Sharing), and restore. Started at launch so no transaction is missed.
///
/// Pro is never synced through iCloud: it belongs to the Apple Account, which can differ from the
/// iCloud one. The last answer is kept on this device so locks don't flicker while StoreKit loads.
@Observable
final class ProStore {
    static let shared = ProStore()

    static let annualID = "alexandrejunior.Stride.pro.annual"
    static let monthlyID = "alexandrejunior.Stride.pro.monthly"
    /// Yearly first: it's the plan we recommend, and the paywall keeps this order.
    static let productIDs = [annualID, monthlyID]

    /// Pro right now.
    private(set) var isPro: Bool
    /// The subscriptions as the App Store sells them here, yearly first. Empty until loaded.
    private(set) var products: [Product] = []
    /// What Profile says about the subscription.
    private(set) var summary = ProSummary(state: .free, detail: ProSummary.freeDetail, canManage: false)

    /// The subscription group, read from the products: a local StoreKit file uses its own id.
    var groupID: String? { products.first?.subscription?.subscriptionGroupID }

    @ObservationIgnored private var updates: Task<Void, Never>?
    /// DEBUG launch argument `-StrideProOverride pro|free`, for screenshots and testing.
    @ObservationIgnored private let override: Bool?

    private init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-StrideProOverride"), arguments.indices.contains(index + 1) {
            override = arguments[index + 1] == "pro"
        } else {
            override = nil
        }
        #else
        override = nil
        #endif
        isPro = override ?? UserDefaults.standard.bool(forKey: StrideSettings.proLastKnown)
    }

    /// Listens for renewals, refunds, Ask to Buy approvals and Family Sharing changes, then checks
    /// what this account has now.
    func start() {
        guard updates == nil else { return }
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                if case .verified(let transaction) = result { await transaction.finish() }
                await self?.refresh()
            }
        }
        Task {
            await loadProducts()
            await refresh()
        }
    }

    func loadProducts() async {
        guard products.isEmpty, let loaded = try? await Product.products(for: Self.productIDs) else { return }
        products = loaded.sorted { (Self.productIDs.firstIndex(of: $0.id) ?? 0) < (Self.productIDs.firstIndex(of: $1.id) ?? 0) }
    }

    /// Re-reads the entitlement. Nothing fires when a subscription simply expires, so this also runs
    /// whenever the app becomes active.
    func refresh() async {
        var active: Transaction?
        for await result in Transaction.currentEntitlements {
            // Unverified transactions don't count; refunded and revoked ones carry a revocation date.
            guard case .verified(let transaction) = result, Self.productIDs.contains(transaction.productID),
                  transaction.revocationDate == nil else { continue }
            active = transaction
        }
        if override == nil {
            isPro = active != nil
            UserDefaults.standard.set(isPro, forKey: StrideSettings.proLastKnown)
        } else {
            isPro = override ?? false
        }
        summary = await makeSummary(for: active)
    }

    /// Restore Purchases: asks the App Store to sync, which may ask the runner to sign in.
    /// Returns a message to show, or nil when Pro is back.
    func restore() async -> String? {
        do {
            try await AppStore.sync()
        } catch {
            return "Couldn't reach the App Store. Check your connection and try again."
        }
        await refresh()
        return isPro ? nil : "No Stride Pro subscription was found for this Apple Account."
    }

    /// The free trial the yearly plan offers this account, if any: "7 days".
    func trialLength() async -> String? {
        guard let annual = products.first(where: { $0.id == Self.annualID }), let subscription = annual.subscription,
              let offer = subscription.introductoryOffer, offer.paymentMode == .freeTrial,
              await subscription.isEligibleForIntroOffer else { return nil }
        return ProPricing.length(offer.period)
    }

    private func makeSummary(for transaction: Transaction?) async -> ProSummary {
        guard let transaction else {
            let trial = await trialLength()
            return ProSummary(state: .free, detail: ProSummary.freeDetail + (trial.map { " Try it free for \($0)." } ?? ""),
                              canManage: false)
        }
        let plan = transaction.productID == Self.annualID ? "Yearly" : "Monthly"
        if transaction.ownershipType == .familyShared {
            return ProSummary(state: .active, detail: "Shared by your family", canManage: false)
        }
        let status = await transaction.subscriptionStatus
        if status?.state == .inGracePeriod {
            return ProSummary(state: .paymentIssue, detail: "Apple couldn't renew it. Check your payment method.", canManage: true)
        }
        var willRenew = true
        if case .verified(let renewal)? = status?.renewalInfo { willRenew = renewal.willAutoRenew }
        let end = transaction.expirationDate.map { shortDate($0, alwaysYear: true) }
        if !willRenew {
            return ProSummary(state: .ending, detail: end.map { "\(plan) · ends \($0)" } ?? plan, canManage: true)
        }
        if transaction.offer?.paymentMode == .freeTrial {
            return ProSummary(state: .trial, detail: end.map { "Free trial · \(plan) from \($0)" } ?? "Free trial", canManage: true)
        }
        return ProSummary(state: .active, detail: end.map { "\(plan) · renews \($0)" } ?? plan, canManage: true)
    }
}

/// Profile's line about the subscription.
struct ProSummary: Equatable {
    enum State { case free, trial, active, ending, paymentIssue }

    var state: State
    var detail: String
    /// Manage subscription is offered; a family member's shared Pro is managed by the organizer.
    var canManage: Bool

    static let freeDetail = "Every plan, intervals, pace alerts and all-time stats."

    /// The status chip beside "Stride Pro", or nil for the way in.
    var chip: (title: String, isWarning: Bool)? {
        switch state {
        case .free: nil
        case .trial: ("Trial", false)
        case .active: ("Active", false)
        case .ending: ("Ending", true)
        case .paymentIssue: ("Payment issue", true)
        }
    }

    static func == (lhs: ProSummary, rhs: ProSummary) -> Bool {
        lhs.state == rhs.state && lhs.detail == rhs.detail && lhs.canManage == rhs.canManage
    }
}

/// Prices and terms in the app's words, from the App Store's localized prices, so the prices set in
/// App Store Connect (Brazil included) read right without code changes.
enum ProPricing {
    /// "US$ 3.33" a month for the yearly plan; nil for monthly.
    static func perMonth(_ product: Product) -> String? {
        guard product.subscription?.subscriptionPeriod.unit == .year else { return nil }
        return (product.price / 12).formatted(product.priceFormatStyle)
    }

    /// Whole percent the yearly plan saves over twelve months of monthly, rounded down; nil under 10%.
    static func savings(of product: Product, against all: [Product]) -> Int? {
        guard product.subscription?.subscriptionPeriod.unit == .year,
              let monthly = all.first(where: { $0.subscription?.subscriptionPeriod.unit == .month }) else { return nil }
        let twelveMonths = NSDecimalNumber(decimal: monthly.price * 12).doubleValue
        guard twelveMonths > 0 else { return nil }
        let percent = Int(((1 - NSDecimalNumber(decimal: product.price).doubleValue / twelveMonths) * 100).rounded(.down))
        return percent >= 10 ? percent : nil
    }

    /// "7 days", "1 month": a trial's length the way people say it.
    static func length(_ period: Product.SubscriptionPeriod) -> String {
        switch period.unit {
        case .day: "\(period.value) \(period.value == 1 ? "day" : "days")"
        case .week: "\(period.value * 7) days"
        case .month: "\(period.value) \(period.value == 1 ? "month" : "months")"
        case .year: "\(period.value) \(period.value == 1 ? "year" : "years")"
        @unknown default: "\(period.value)"
        }
    }
}
