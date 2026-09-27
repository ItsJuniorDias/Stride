import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Progress: likely 5K, 10K, half and marathon times from the runner's recent best efforts, and the
/// paces to train at. Stride Pro; without it, what the card shows in words and the way in.
struct RacePredictorCard: View {
    let entries: [RecordEntry]
    let now: Date
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var upsell: ProFeature?
    @State private var showsInfo = false

    private var isLocked: Bool { !ProStore.shared.isPro }

    var body: some View {
        let result = isLocked ? nil : RacePredictor.predict(from: entries, now: now)
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(spacing: Space.x2) {
                Text("Race predictions")
                    .font(.headline)
                    .foregroundStyle(.ink)
                    .accessibilityAddTraits(.isHeader)
                if isLocked { TagBadge("Pro") }
                Spacer(minLength: 0)
                if result != nil { infoButton }
            }
            .frame(minHeight: 28)

            if showsInfo, let result {
                Text(caption(result.basis))
                    .font(.footnote)
                    .foregroundStyle(.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(Space.x3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.laneSoft, in: RoundedRectangle(cornerRadius: Radius.md))
                    .transition(.opacity)
            }

            if isLocked {
                ProgressProTeaser(symbol: "flag.checkered",
                                  text: "Your likely 5K, 10K, half and marathon times, and the paces to train at.") {
                    upsell = .racePredictor
                }
            } else if let result {
                predictions(result)
                if let paces = result.trainingPaces {
                    TrainAtRow(paces: paces, unit: unit)
                }
            } else {
                Text("Run a few more times to see what you could race over 5K, 10K, the half and the marathon.")
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .raisedCard()
        .proPaywall($upsell)
    }

    private var infoButton: some View {
        Button {
            withAnimation(.snappy) { showsInfo.toggle() }
        } label: {
            Image(systemName: showsInfo ? "info.circle.fill" : "info.circle")
                .font(.system(size: 20))
                .foregroundStyle(.lane)
                .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The tap target reaches into the card's padding, as drawn.
        .padding(.vertical, -8)
        .padding(.trailing, -12)
        .accessibilityLabel("How predictions work")
        .accessibilityValue(showsInfo ? "Shown" : "Hidden")
    }

    /// The four races on sunken tiles, two by two.
    private func predictions(_ result: RacePredictions) -> some View {
        let races = RacePredictor.races
        return Grid(horizontalSpacing: Space.x2, verticalSpacing: Space.x2) {
            ForEach(Array(stride(from: 0, to: races.count, by: 2)), id: \.self) { start in
                GridRow {
                    ForEach(races[start..<min(start + 2, races.count)]) { race in
                        PredictionTile(race: race, prediction: result[race], unit: unit)
                    }
                }
            }
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

/// A race, its predicted time and pace, on a sunken tile.
private struct PredictionTile: View {
    let race: EffortDistance
    let prediction: RacePrediction?
    let unit: UnitSystem

    var body: some View {
        StatTile(race.sentenceTitle,
                 value: prediction.map { RunFormat.duration($0.time) } ?? RunFormat.empty,
                 size: .medium,
                 tint: prediction == nil ? .inkMuted : .ink,
                 footnote: footnote)
            .frame(maxHeight: .infinity, alignment: .top)
            .raisedCard(padding: Space.x3, fill: .surfaceSunken)
            .accessibilityHint(source)
    }

    /// `4'48" /km`, or what it takes to see one.
    private var footnote: String {
        guard let prediction else {
            guard let shortest = RacePredictor.shortestEffort(for: race) else { return "Not enough runs yet" }
            return "Run \(shortest == .oneMile ? "a mile" : "a " + shortest.title) or longer"
        }
        return "\(RunFormat.pace(prediction.pace(in: unit))) \(unit.paceSymbol)"
    }

    private var source: String {
        guard let prediction else { return "" }
        return "From your \(prediction.source == .oneMile ? "mile" : prediction.source.title)"
    }
}

/// Easy, tempo and interval paces under the predictions, and the way to all five.
private struct TrainAtRow: View {
    let paces: TrainingPaces
    let unit: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            HStack {
                Text("Train at").metricLabelStyle()
                Spacer(minLength: Space.x2)
                NavigationLink(value: ProgressRoute.trainingPaces) {
                    LinkLabel("All 5 paces", showsChevron: true)
                }
                .buttonStyle(.strideLink)
                .padding(.vertical, -14)
            }
            HStack(alignment: .top, spacing: Space.x2) {
                ForEach([TrainingPaces.Intensity.easy, .threshold, .interval]) { intensity in
                    let pace = paces.unitless(intensity, unit: unit)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(intensity.title)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.inkMuted)
                        Text(pace)
                            .font(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(intensity.title) pace")
                    .accessibilityValue("\(pace) \(unit.paceSymbol)")
                }
            }
        }
        .padding(.top, Space.x3)
        .overlay(alignment: .top) { Hairline() }
    }
}

extension TrainingPaces {
    /// `5'24"`, or `6'15"–6'45"` for easy running, per the runner's unit, without the unit: for tiles
    /// and columns whose heading already says it.
    func unitless(_ intensity: Intensity, unit: UnitSystem) -> String {
        let bounds = range(intensity)
        let fast = RunFormat.pace(Self.perUnit(bounds.lowerBound, unit: unit))
        let slow = RunFormat.pace(Self.perUnit(bounds.upperBound, unit: unit))
        return fast == slow ? fast : fast + "–" + slow
    }
}

private extension EffortDistance {
    /// "5K", "10K", "Half marathon", "Marathon": sentence case for tiles.
    var sentenceTitle: String {
        title.prefix(1).uppercased() + String(title.dropFirst())
    }
}

/// Every training pace, what it's for and how fast, from the runner's predicted 5K. Stride Pro.
struct TrainingPacesView: View {
    @Query(sort: \Run.startDate, order: .reverse) private var runs: [Run]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var upsell: ProFeature?

    var body: some View {
        let paces = ProStore.shared.isPro ? RacePredictor.predict(from: runs.map(\.recordEntry))?.trainingPaces : nil
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x3) {
                if !ProStore.shared.isPro {
                    ProgressProTeaser(symbol: "gauge.with.needle",
                                      text: "Easy, marathon, tempo, interval and repetition paces from your best efforts.") {
                        upsell = .racePredictor
                    }
                    .raisedCard()
                } else if let paces {
                    Text("From your predicted 5K, \(RunFormat.duration(paces.fiveKTime)). They update as your best efforts improve.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    GroupedCard {
                        ForEach(TrainingPaces.Intensity.allCases) { intensity in
                            CardRow(intensity.title, subtitle: intensity.detail) {
                                Text("\(paces.unitless(intensity, unit: unit)) \(unit.paceSymbol)")
                                    .font(.body.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(.ink)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                } else {
                    Text("Run a few more times and your training paces show up here.")
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                        .raisedCard()
                }
            }
            .padding(Space.x4)
        }
        .background(Color.surface)
        .navigationTitle("Training paces")
        .navigationBarTitleDisplayMode(.inline)
        .proPaywall($upsell)
    }
}

/// A Pro card on Progress without Pro: what it shows, in words only, and the way to Stride Pro. Sits
/// inside the card it stands in for.
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
    }
}
