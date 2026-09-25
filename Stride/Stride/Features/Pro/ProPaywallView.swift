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

    var id: Self { self }

    var headline: String {
        switch self {
        case .general: "Free to run. Pro to improve."
        case .plan: "Unlock every training plan"
        case .intervals: "Train with intervals"
        case .targetPace: "Hold the pace you want"
        case .stats: "See the long view"
        case .challenges: "Set your own challenges"
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
        }
    }

    var illustration: String {
        switch self {
        case .general: "planHalfMarathon"
        case .plan(let id): TrainingPlan.plan(id: id)?.coverImage ?? "plan10k"
        case .intervals: "plan10k"
        case .targetPace: "watchRun"
        case .stats: "recordsTrophy"
        case .challenges: "challengeMountain"
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
        case .plans: "Every training plan"
        case .intervals: "Interval workouts"
        case .targetPace: "Target-pace alerts"
        case .stats: "Year and all-time stats"
        case .challenges: "Your own challenges"
        case .family: "Family Sharing"
        }
    }

    var detail: String {
        switch self {
        case .plans: "10K and Half Marathon, and every plan added later."
        case .intervals: "Structured repeats with the coach calling each step."
        case .targetPace: "A word in your ear when you drift off pace."
        case .stats: "Totals and charts for every year you've run."
        case .challenges: "Any target, any time frame."
        case .family: "Share Pro with up to five family members."
        }
    }

    /// Every benefit with the one `feature` asked about first; Family Sharing stays last.
    static func ordered(first feature: ProFeature) -> [ProBenefit] {
        guard let lead = feature.benefit else { return allCases }
        return [lead] + allCases.filter { $0 != lead }
    }
}

/// Stride Pro: what brought the runner here, what Pro adds, and the two plans with yearly first.
/// Recording runs and the runner's own data are never behind it.
struct ProPaywallView: View {
    let feature: ProFeature
    @Environment(\.dismiss) private var dismiss
    private var pro: ProStore { .shared }

    var body: some View {
        SubscriptionStoreView(productIDs: ProStore.productIDs) {
            ProMarketingContent(feature: feature)
        }
        .subscriptionStoreControlStyle(.prominentPicker)
        .subscriptionStoreButtonLabel(.multiline)
        .storeButton(.visible, for: .restorePurchases, .policies, .cancellation)
        .subscriptionStorePolicyDestination(url: AppInfo.termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: AppInfo.privacyURL, for: .privacyPolicy)
        .containerBackground(Color.surface, for: .subscriptionStoreFullHeight)
        .tint(.track)
        .onInAppPurchaseCompletion { _, result in
            guard case .success(.success(let verification)) = result, case .verified(let transaction) = verification else { return }
            await transaction.finish()
            await pro.refresh()
            dismiss()
        }
        // A restore, or a purchase finished on another device, also closes it.
        .onChange(of: pro.isPro) { _, isPro in
            if isPro { dismiss() }
        }
    }
}

/// The paywall above the plans: artwork, the reason the runner is here, what Pro adds, and what
/// stays free.
struct ProMarketingContent: View {
    let feature: ProFeature

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            VStack(alignment: .leading, spacing: Space.x3) {
                Illustration(name: feature.illustration, contentMode: .fill)
                    .frame(height: 190)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                    .padding(.bottom, Space.x1)
                Label("Stride Pro", systemImage: "bolt.fill")
                    .font(.metricLabel)
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(.track)
                Text(feature.headline).font(.title2.bold()).foregroundStyle(.ink)
                Text(feature.message).font(.subheadline).foregroundStyle(.inkMuted)
            }
            VStack(alignment: .leading, spacing: Space.x4) {
                ForEach(ProBenefit.ordered(first: feature)) { ProBenefitRow(benefit: $0) }
            }
            .raisedCard()
            Label("Recording runs, your history and maps, Apple Health, widgets, shoes and friends stay free.",
                  systemImage: "checkmark.seal")
                .font(.footnote)
                .foregroundStyle(.inkMuted)
        }
        .padding(.horizontal, Space.x4)
        .padding(.top, Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// One thing Pro adds: its symbol, a name and a line.
struct ProBenefitRow: View {
    let benefit: ProBenefit

    var body: some View {
        HStack(spacing: Space.x3) {
            ProSymbol(benefit.symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(benefit.title).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                Text(benefit.detail).font(.caption).foregroundStyle(.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
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
