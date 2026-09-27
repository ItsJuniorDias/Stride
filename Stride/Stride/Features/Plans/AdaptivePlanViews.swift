import Foundation
import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// The runner's training paces from their best efforts (see ``RacePredictor``): targets for plan
/// sessions and the workout builder. Callers decide whether Stride Pro lets them be used.
enum PersonalPaces {
    static func from(_ runs: [Run]) -> TrainingPaces? {
        RacePredictor.predict(from: runs.map(\.recordEntry))?.trainingPaces
    }

    static func current(in context: ModelContext) -> TrainingPaces? {
        from((try? context.fetch(FetchDescriptor<Run>())) ?? [])
    }

    /// Changes when the paces may have (Pro, a run added or removed), for `.task(id:)`. `runs` newest first.
    static func key(for runs: [Run]) -> String {
        "\(ProStore.shared.isPro)-\(runs.count)-\(runs.first?.startDate.timeIntervalSince1970 ?? 0)"
    }

    /// "Tempo pace 5'24" /km", or "Easy pace 6'15"–6'45" /km".
    static func line(_ intensity: TrainingPaces.Intensity, paces: TrainingPaces, unit: UnitSystem) -> String {
        "\(intensity.title) pace \(paces.formatted(intensity, unit: unit))"
    }
}

/// Where the runner is in a plan: what's done, a week being run again after a break, what's next,
/// and whether a break suggests going back a week. Shared by Home and the plan screen.
struct PlanState {
    let completed: Set<String>
    /// The repeat in progress for this plan; nil once its weeks have all been run again.
    let repeating: PlanRepeat?
    /// A repeated session first, then the first one not done.
    let next: Workout?
    /// Where the plan really is (0-based week), to skip a repeat and go back to it.
    let resumeWeek: Int?
    /// The week to suggest starting again from after a break (0-based), unless the runner said not now.
    let suggestedRepeatWeek: Int?
    /// Whole weeks since the last run, for the suggestion.
    let weeksAway: Int

    /// `runs` newest first, as the plan screens query them.
    init(plan: TrainingPlan, completedRaw: String, repeatRaw: String, dismissedLastRun: Double, runs: [Run],
         now: Date = .now) {
        let completed = PlanProgress.completed(from: completedRaw)
        let candidate = PlanRepeat(rawValue: repeatRaw).flatMap { $0.planID == plan.id ? $0 : nil }
        // Plan runs since the repeat started: a run of a session counts toward it.
        let runSince: Set<String> = candidate.map { repeating in
            Set(runs.prefix(while: { $0.startDate >= repeating.since }).compactMap(\.planSessionID))
        } ?? []
        let repeated = plan.repeatedSession(completed: completed, repeating: candidate, runSince: runSince)
        let planNext = plan.nextSession(completed: completed)
        self.completed = completed
        self.repeating = repeated == nil ? nil : candidate
        self.next = repeated ?? planNext
        self.resumeWeek = planNext.flatMap { plan.week(of: $0.id) }

        let lastRun = runs.first?.startDate
        let dismissed = lastRun.map { abs($0.timeIntervalSince1970 - dismissedLastRun) < 1 } ?? false
        self.suggestedRepeatWeek = repeated == nil && !dismissed
            ? plan.suggestedRepeatWeek(completed: completed, lastRunDate: lastRun, now: now)
            : nil
        self.weeksAway = lastRun.map { TrainingPlan.daysBetween($0, and: now) / 7 } ?? 0
    }
}

/// After a break: start again from the last full week before carrying on. Nothing is marked done or
/// undone either way, and it's never more than a suggestion.
struct PlanRepeatCallout: View {
    /// 0-based.
    let week: Int
    let weeksAway: Int
    let onRepeat: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(alignment: .top, spacing: Space.x3) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.track)
                    .frame(width: 40, height: 40)
                    .background(Color.surfaceRaised, in: Circle())
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Welcome back").font(.headline).foregroundStyle(.ink)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HStack(spacing: Space.x4) {
                Button(action: onRepeat) {
                    Text("Restart from week \(week + 1)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.ink)
                        .padding(.horizontal, Space.x4)
                        .frame(minHeight: 36)
                        .background(Color.surfaceRaised, in: Capsule())
                        .contentShape(Capsule())
                }
                // Plain, so each button in a List row takes only its own taps.
                .buttonStyle(.plain)
                Button("Not now", action: onDismiss)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.lane)
                    .buttonStyle(.plain)
            }
            // Under the words, past the symbol.
            .padding(.leading, 40 + Space.x3)
        }
        .padding(Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.trackSoft, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private var message: String {
        let away = weeksAway >= 2 ? "It's been \(weeksAway) weeks since your last run." : "It's been a while since your last run."
        return "\(away) Picking up again from week \(week + 1) is a gentle way back in. Your progress stays as it is."
    }
}

/// While weeks are being run again: from which week, and a way back to where the plan was.
struct PlanRepeatStatus: View {
    /// 0-based, both.
    let week: Int
    let resumeWeek: Int?
    let onSkip: () -> Void

    var body: some View {
        HStack(spacing: Space.x2) {
            Label("Restarted from week \(week + 1)", systemImage: "arrow.counterclockwise")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.track)
            Spacer(minLength: Space.x2)
            if let resumeWeek {
                Button("Skip to week \(resumeWeek + 1)", action: onSkip)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.lane)
                    .buttonStyle(.plain)
            }
        }
    }
}

/// "Your paces" on a plan screen: easy, tempo and interval on sunken tiles, from the runner's
/// predicted 5K; or why they aren't there yet. Stride Pro; without it, what they do and the way in.
struct PersonalPacesCard: View {
    let paces: TrainingPaces?
    let unit: UnitSystem
    let isLocked: Bool
    let onUpsell: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.x2) {
                    Text("Your paces")
                        .font(.headline)
                        .foregroundStyle(.ink)
                        .accessibilityAddTraits(.isHeader)
                    if isLocked { TagBadge("Pro") }
                }
                if !isLocked, let paces {
                    Text("Updated from your predicted 5K, \(RunFormat.duration(paces.fiveKTime)).")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.inkMuted)
                }
            }
            if isLocked {
                ProUpsellRow(symbol: "gauge.with.needle", title: "Paces that fit you",
                             detail: "Tempo and interval targets from your best efforts, called by the coach.",
                             action: onUpsell)
            } else if let paces {
                // The easy range is the widest, so its tile is too.
                WeightedColumns(weights: [1.4, 1, 1], spacing: Space.x2) {
                    tile(.easy, footnote: "Most runs", paces: paces)
                    tile(.threshold, footnote: "Tempo runs", paces: paces)
                    tile(.interval, footnote: "Repeats", paces: paces)
                }
            } else {
                Label("Run a few times and your paces appear here.", systemImage: "gauge.with.needle")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
            }
        }
        .raisedCard()
    }

    private func tile(_ intensity: TrainingPaces.Intensity, footnote: String, paces: TrainingPaces) -> some View {
        let pace = paces.unitless(intensity, unit: unit)
        return VStack(alignment: .leading, spacing: 0) {
            Text(intensity.title).metricLabelStyle()
            Text(pace)
                .font(.subheadline.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.top, 6)
            Text(footnote)
                .font(.footnote)
                .foregroundStyle(.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 2)
        }
        .padding(.vertical, Space.x3)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceSunken, in: RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(intensity.title) pace, \(footnote.lowercased())")
        .accessibilityValue("\(pace) \(unit.paceSymbol)")
    }
}

/// Columns whose widths follow `weights` (1.4, 1, 1 gives the first 40% more room), all as tall as
/// the tallest.
nonisolated struct WeightedColumns: Layout {
    let weights: [CGFloat]
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }
            + spacing * CGFloat(max(subviews.count - 1, 0))
        let widths = columnWidths(total: width, count: subviews.count)
        let height = zip(subviews, widths).map { subview, width in
            subview.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
        }.max() ?? 0
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let widths = columnWidths(total: bounds.width, count: subviews.count)
        var x = bounds.minX
        for (subview, width) in zip(subviews, widths) {
            subview.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: width, height: bounds.height))
            x += width + spacing
        }
    }

    private func columnWidths(total: CGFloat, count: Int) -> [CGFloat] {
        guard count > 0 else { return [] }
        let shares = (0..<count).map { $0 < weights.count ? weights[$0] : 1 }
        let sum = shares.reduce(0, +)
        let available = max(total - spacing * CGFloat(count - 1), 0)
        return shares.map { available * $0 / max(sum, 0.001) }
    }
}
