import SwiftUI
import StoreKit
import StrideKit
import StrideUI

/// Why Stride Pro was opened. Sets the paywall's headline, message and artwork so it answers the
/// tap that led there, and lists the matching benefit first.
enum ProFeature: Hashable, Identifiable {
    case general
    /// A training plan, by id.
    case plan(String)
    case intervals, targetPace, stats, challenges
    /// Race predictions from the runner's best efforts.
    case racePredictor
    /// Training load and pace trends.
    case trends
    /// Building your own interval workouts.
    case workouts

    var id: Self { self }

    var headline: String {
        switch self {
        case .general: "Free to run. Pro to improve."
        case .plan: "Unlock every training plan"
        case .intervals: "Train with intervals"
        case .targetPace: "Hold the pace you want"
        case .stats: "See the long view"
        case .challenges: "Set your own challenges"
        case .racePredictor: "Know what you can run"
        case .trends: "Train smart, not just hard"
        case .workouts: "Build your own workouts"
        }
    }

    var message: String {
        switch self {
        case .general:
            "Plans, intervals and pace alerts to get faster, and the long view to see it happen."
        case .plan(let id):
            TrainingPlan.plan(id: id).map { "Follow the \($0.name) plan week by week, with a coach in your ear." }
                ?? "Every plan, week by week, with a coach in your ear."
        case .intervals: "Repeats, recoveries and warm-ups, with the coach calling every step."
        case .targetPace: "Pick a pace and the coach tells you when you drift more than 10 seconds off it."
        case .stats: "Every month of the year and every year since your first run, side by side."
        case .challenges: "Choose what counts, how much, and by when."
        case .racePredictor: "Your likely 5K, 10K, half and marathon times, from how you run today."
        case .trends: "Your training load against your usual, and how your pace is moving."
        case .workouts: "Repeats, recoveries and targets your way, saved and ready on iPhone and Apple Watch."
        }
    }

    var benefit: ProBenefit? {
        switch self {
        case .general: nil
        case .plan: .plans
        case .intervals: .intervals
        case .targetPace: .targetPace
        case .stats: .stats
        case .challenges: .challenges
        case .racePredictor, .trends: .stats
        case .workouts: .intervals
        }
    }
}

/// What Pro adds, in the order the paywall lists it.
enum ProBenefit: CaseIterable, Identifiable {
    case plans, intervals, targetPace, stats, challenges, family

    var id: Self { self }

    var symbol: String {
        switch self {
        case .plans: "calendar.badge.checkmark"
        case .intervals: "repeat"
        case .targetPace: "gauge.with.needle"
        case .stats: "chart.bar.xaxis"
        case .challenges: "flag.checkered"
        case .family: "person.2.fill"
        }
    }

    var title: String {
        switch self {
        case .plans: "Plans that adapt to you"
        case .intervals: "Intervals and your own workouts, on your wrist"
        case .targetPace: "Target-pace alerts"
        case .stats: "Race predictions, trends and all-time stats"
        case .challenges: "Your own challenges"
        case .family: "Family Sharing"
        }
    }

    /// Every benefit with the one `feature` asked about first; Family Sharing stays last.
    static func ordered(first feature: ProFeature) -> [ProBenefit] {
        guard let lead = feature.benefit else { return allCases }
        return [lead] + allCases.filter { $0 != lead }
    }
}

/// Stride Pro, as designed: why the runner is here, what Pro adds on a glass card, then the two plans
/// (yearly first) with the button and billing terms at the bottom. Restore, Terms of Use and Privacy
/// Policy sit in the footer (App Review 3.1.2). Recording runs and the runner's own data are never
/// behind it.
struct ProPaywallView: View {
    let feature: ProFeature
    @Environment(\.dismiss) private var dismiss
    @Environment(\.purchase) private var purchase
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedID = ProStore.annualID
    /// Plans whose free trial this Apple Account can still take.
    @State private var trialIDs: Set<Product.ID> = []
    @State private var isPurchasing = false
    @State private var isRestoring = false
    @State private var message: String?
    @State private var loadFailed = false
    private var pro: ProStore { .shared }

    private var selected: Product? {
        pro.products.first { $0.id == selectedID } ?? pro.products.first
    }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    benefits
                        .padding(.top, Space.x5)
                    // At least 32 pt between what Pro adds and the prices; spare height goes here, so
                    // the plans and the button sit at the bottom on taller screens.
                    Spacer(minLength: Space.x6)
                    plans
                    purchaseBar
                        .padding(.top, Space.x3)
                }
                .padding(.horizontal, Space.x4)
                .padding(.top, Space.x7 + Space.x2)
                .padding(.bottom, Space.x4)
                .frame(minHeight: geo.size.height, alignment: .top)
                .background(alignment: .topLeading) { glow(width: geo.size.width) }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color.surface)
        .overlay(alignment: .topTrailing) { closeButton }
        .task { await load() }
        .sensoryFeedback(.selection, trigger: selectedID)
        // A restore, or a purchase approved elsewhere (Ask to Buy), also closes it.
        .onChange(of: pro.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Label("Stride Pro", systemImage: "bolt.fill")
                .font(.metricLabel)
                .tracking(1.3)
                .textCase(.uppercase)
                .foregroundStyle(.track)
            Text(feature.headline).font(.title.bold()).foregroundStyle(.ink)
            Text(feature.message).font(.subheadline).foregroundStyle(.inkMuted)
        }
        // Clear of the close button.
        .padding(.trailing, Space.x6)
    }

    /// What Pro adds, one line each on Liquid Glass (a material before iOS 26).
    private var benefits: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            ForEach(ProBenefit.ordered(first: feature)) { benefit in
                HStack(spacing: Space.x3) {
                    Image(systemName: benefit.symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.track)
                        .frame(width: 28, height: 28)
                        .background(Color.trackSoft, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .accessibilityHidden(true)
                    Text(benefit.title).font(.callout.weight(.medium)).foregroundStyle(.ink)
                }
            }
        }
        .padding(Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassPanel(cornerRadius: Radius.lg)
    }

    /// The soft brand and data colors behind the glass card, so the glass has something to show.
    private func glow(width: CGFloat) -> some View {
        let dark = colorScheme == .dark
        return ZStack(alignment: .topLeading) {
            Circle()
                .fill(Color.track)
                .frame(width: 270, height: 270)
                .opacity(dark ? 0.34 : 0.22)
                .blur(radius: 72)
                .offset(x: -70, y: 190)
            Circle()
                .fill(Color.lane)
                .frame(width: 230, height: 230)
                .opacity(dark ? 0.26 : 0.18)
                .blur(radius: 72)
                .offset(x: width - 170, y: 330)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var plans: some View {
        if pro.products.isEmpty {
            VStack(spacing: Space.x3) {
                if loadFailed {
                    Text("Stride Pro isn't available right now.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                    Button("Try again") { Task { await load() } }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.lane)
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity, minHeight: 160)
        } else {
            VStack(spacing: Space.x2 + 2) {
                ForEach(pro.products) { product in
                    ProPlanOption(product: product, trial: trialOffer(for: product),
                                  savings: ProPricing.savings(of: product, against: pro.products),
                                  isSelected: product.id == selected?.id) {
                        selectedID = product.id
                    }
                }
            }
        }
    }

    /// The button, what it charges and when, then restore and the policies.
    private var purchaseBar: some View {
        VStack(spacing: Space.x2) {
            Button {
                Task { await buy() }
            } label: {
                if isPurchasing {
                    ProgressView()
                } else {
                    Text(selected.map { trialOffer(for: $0) != nil } == true ? "Start free trial" : "Subscribe")
                }
            }
            .buttonStyle(.stridePrimary)
            .disabled(selected == nil || isPurchasing)

            if let selected {
                Text(ProPricing.terms(for: selected, trial: trialOffer(for: selected)))
                    .font(.caption)
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
            }
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.warning)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: Space.x2) {
                Button(isRestoring ? "Restoring…" : "Restore") { Task { await restore() } }
                    .disabled(isRestoring)
                Text("·").accessibilityHidden(true)
                Link("Terms of Use", destination: AppInfo.termsURL)
                Text("·").accessibilityHidden(true)
                Link("Privacy Policy", destination: AppInfo.privacyURL)
            }
            .font(.footnote)
            .foregroundStyle(.inkMuted)
            .tint(.inkMuted)
        }
        .frame(maxWidth: .infinity)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.footnote.weight(.bold))
                .foregroundStyle(.inkMuted)
                .frame(width: 32, height: 32)
                .background(Color.surfaceRaised, in: Circle())
                .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Close")
        .padding(.top, Space.x3)
        .padding(.trailing, Space.x3)
    }

    /// The free trial `product` offers this account, only when it's eligible, so it's never promised
    /// to someone who already had it.
    private func trialOffer(for product: Product) -> Product.SubscriptionOffer? {
        trialIDs.contains(product.id) ? product.subscription?.introductoryOffer : nil
    }

    private func load() async {
        loadFailed = false
        await pro.loadProducts()
        loadFailed = pro.products.isEmpty
        var eligible: Set<Product.ID> = []
        for product in pro.products {
            guard let subscription = product.subscription, subscription.introductoryOffer?.paymentMode == .freeTrial else { continue }
            if await subscription.isEligibleForIntroOffer { eligible.insert(product.id) }
        }
        trialIDs = eligible
    }

    private func buy() async {
        guard let product = selected else { return }
        isPurchasing = true
        message = nil
        defer { isPurchasing = false }
        do {
            switch try await purchase(product) {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    message = "The App Store couldn't verify this purchase. Try again."
                    return
                }
                await transaction.finish()
                await pro.refresh()
                dismiss()
            case .pending:
                message = "Waiting for approval. Stride Pro unlocks as soon as it's approved."
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            message = "The purchase didn't go through. Try again."
        }
    }

    private func restore() async {
        isRestoring = true
        message = await pro.restore()
        isRestoring = false
    }
}

/// One plan: a selection mark, its name, the price billed (with the free trial when there is one)
/// and, for yearly, the monthly equivalent in smaller type.
private struct ProPlanOption: View {
    let product: Product
    let trial: Product.SubscriptionOffer?
    let savings: Int?
    let isSelected: Bool
    let action: () -> Void

    private var isYearly: Bool { product.subscription?.subscriptionPeriod.unit == .year }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.x3 + 2) {
                selectionMark
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: Space.x2) {
                        Text(isYearly ? "Yearly" : "Monthly").font(.headline).foregroundStyle(.ink)
                        if isYearly, let savings { TagBadge("Save \(savings)%") }
                    }
                    Text(ProPricing.price(product, trial: trial))
                        .font(.subheadline)
                        .foregroundStyle(.ink)
                    if let perMonth = ProPricing.perMonth(product) {
                        Text("\(perMonth) a month").font(.caption).foregroundStyle(.inkMuted)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, Space.x3)
            .padding(.horizontal, Space.x4)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                    .strokeBorder(isSelected ? Color.track : Color.line, lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
            .animation(.snappy(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    /// A filled brand circle with a check when selected, an empty ring otherwise.
    @ViewBuilder private var selectionMark: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .font(.caption.weight(.heavy))
                .foregroundStyle(.onTrack)
                .frame(width: 24, height: 24)
                .background(Color.track, in: Circle())
        } else {
            Circle()
                .strokeBorder(Color.line, lineWidth: 2)
                .frame(width: 24, height: 24)
        }
    }
}

/// A symbol in a soft brand circle, sized like ``ChallengeIcon``.
struct ProSymbol: View {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    var body: some View {
        Image(systemName: name)
            .font(.body.weight(.semibold))
            .foregroundStyle(.track)
            .frame(width: 40, height: 40)
            .background(Color.trackSoft, in: Circle())
            .accessibilityHidden(true)
    }
}

/// Stands in for a Pro control in a form or list: what it does, the PRO tag, and a tap to the paywall.
struct ProUpsellRow: View {
    let symbol: String
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Space.x3) {
                ProSymbol(symbol)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                    Text(detail).font(.caption).foregroundStyle(.inkMuted)
                }
                Spacer(minLength: 0)
                TagBadge("Pro")
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens Stride Pro")
    }
}

extension View {
    /// Presents Stride Pro for the feature the runner tapped. Each screen owns its sheet, like its
    /// other sheets, so this also works from inside a sheet such as New challenge.
    func proPaywall(_ feature: Binding<ProFeature?>) -> some View {
        sheet(item: feature) { ProPaywallView(feature: $0) }
    }
}

#Preview {
    ProPaywallView(feature: .general)
}
