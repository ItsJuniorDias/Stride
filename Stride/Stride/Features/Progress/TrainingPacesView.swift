import SwiftUI
import SwiftData
import StrideKit
import StrideUI

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
