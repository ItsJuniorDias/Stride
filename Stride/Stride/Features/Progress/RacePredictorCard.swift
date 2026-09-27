import SwiftUI
import StrideKit
import StrideUI

/// Progress: likely 5K, 10K, half and marathon times from the runner's recent best efforts, and the
/// paces to train at. Stride Pro; without it, what the card shows in words and the way in.
struct RacePredictorCard: View {
    let entries: [RecordEntry]
    let now: Date
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var upsell: ProFeature?

    private var isLocked: Bool { !ProStore.shared.isPro }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x2) {
                Text("Race predictions").font(.headline).foregroundStyle(.ink)
                if isLocked { TagBadge("Pro") }
                Spacer()
            }
            .accessibilityElement(children: .combine)

            if isLocked {
                ProgressProTeaser(symbol: "flag.checkered",
                                  text: "Your likely 5K, 10K, half and marathon times, and the paces to train at.") {
                    upsell = .racePredictor
                }
            } else if let result = RacePredictor.predict(from: entries, now: now) {
                predictions(result)
            } else {
                Text("Run a few more times to see what you could race over 5K, 10K, the half and the marathon.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .raisedCard()
            }
        }
        .proPaywall($upsell)
    }

    private func predictions(_ result: RacePredictions) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            VStack(spacing: 0) {
                ForEach(Array(RacePredictor.races.enumerated()), id: \.element.id) { index, race in
                    if index > 0 { Divider().padding(.leading, Space.x4) }
                    PredictionRow(race: race, prediction: result[race], unit: unit)
                }
                if let paces = result.trainingPaces {
                    Divider()
                    TrainingPacesList(paces: paces, unit: unit)
                }
            }
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
            Text(caption(result.basis))
                .font(.caption)
                .foregroundStyle(.inkMuted)
        }
    }

    private func caption(_ basis: RacePredictions.Basis) -> String {
        let source = switch basis {
        case .recent: "From your best efforts in the last \(RacePredictor.recentDays) days."
        case .allTime: "From your best efforts ever: there are too few runs in the last \(RacePredictor.recentDays) days."
        }
        return "\(source) The half and marathon assume you've trained for the distance."
    }
}

/// A race, its predicted time and pace, and the effort it comes from.
private struct PredictionRow: View {
    let race: EffortDistance
    let prediction: RacePrediction?
    let unit: UnitSystem

    var body: some View {
        HStack(spacing: Space.x3) {
            VStack(alignment: .leading, spacing: 2) {
                Text(raceTitle(race)).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                Text(detail).font(.caption).foregroundStyle(.inkMuted)
            }
            Spacer(minLength: Space.x2)
            Text(prediction.map { RunFormat.duration($0.time) } ?? RunFormat.empty)
                .font(.metricSmall)
                .monospacedDigit()
                .foregroundStyle(prediction == nil ? Color.inkMuted : Color.ink)
        }
        .padding(.horizontal, Space.x4)
        .padding(.vertical, Space.x3)
        .frame(minHeight: Dimension.hitMin)
        .accessibilityElement(children: .combine)
    }

    private var detail: String {
        guard let prediction else {
            guard let shortest = RacePredictor.shortestEffort(for: race) else { return "Not enough runs yet" }
            let effort = shortest == .oneMile ? "a mile" : "a " + shortest.title
            return "Run \(effort) or longer to see it"
        }
        let pace = RunFormat.pace(prediction.pace(in: unit))
        let source = prediction.source == .oneMile ? "mile" : prediction.source.title
        return "\(pace) \(unit.paceSymbol) · from your \(source)"
    }

    /// "5K", "10K", "Half marathon", "Marathon".
    private func raceTitle(_ race: EffortDistance) -> String {
        race.title.prefix(1).uppercased() + String(race.title.dropFirst())
    }
}

/// Easy, marathon, tempo, interval and repetition paces from the 5K prediction.
private struct TrainingPacesList: View {
    let paces: TrainingPaces
    let unit: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text("Training paces").metricLabelStyle()
            ForEach(TrainingPaces.Intensity.allCases) { intensity in
                HStack(alignment: .firstTextBaseline, spacing: Space.x3) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(intensity.title).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                        Text(intensity.detail).font(.caption).foregroundStyle(.inkMuted)
                    }
                    Spacer(minLength: Space.x2)
                    Text(value(intensity))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.ink)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `5'24"`, or `6'15"–6'45"` for easy runs, per the runner's unit.
    private func value(_ intensity: TrainingPaces.Intensity) -> String {
        let range = paces.range(intensity)
        let fast = RunFormat.pace(TrainingPaces.perUnit(range.lowerBound, unit: unit))
        let slow = RunFormat.pace(TrainingPaces.perUnit(range.upperBound, unit: unit))
        let pace = fast == slow ? fast : fast + "–" + slow
        return "\(pace) \(unit.paceSymbol)"
    }
}

/// A Pro card on Progress without Pro: what it shows, in words only, and the way to Stride Pro.
struct ProgressProTeaser: View {
    let symbol: String
    let text: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x3) {
                ProSymbol(symbol)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button("See Stride Pro", action: action)
                .buttonStyle(.strideSecondary)
        }
        .raisedCard()
    }
}
