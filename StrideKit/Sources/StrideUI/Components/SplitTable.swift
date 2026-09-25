import SwiftUI
import StrideKit

/// Per-unit splits with a speed bar scaled between the slowest (40%) and fastest (100%) split.
/// The fastest full split is the only highlight.
public struct SplitTable: View {
    let splits: [Split]
    let unit: UnitSystem

    public init(splits: [Split], unit: UnitSystem) {
        self.splits = splits
        self.unit = unit
    }

    /// Pace range of the full splits, used to scale the bars.
    private var paceRange: ClosedRange<Double>? {
        let paces = splits.filter { !$0.isPartial(in: unit) }.compactMap { $0.pace(in: unit) }
        guard let fastest = paces.min(), let slowest = paces.max() else { return nil }
        return fastest...slowest
    }

    /// 1 for the fastest split, 0.4 for the slowest, linear in between.
    private func barFraction(for pace: Double?) -> Double {
        guard let pace, let range = paceRange, range.upperBound > range.lowerBound else { return 1 }
        let position = (range.upperBound - pace) / (range.upperBound - range.lowerBound)
        return min(max(0.4 + 0.6 * position, 0.4), 1)
    }

    public var body: some View {
        let fastest = Split.fastest(in: splits, unit: unit)
        VStack(spacing: Space.x2) {
            HStack(spacing: Space.x3) {
                Text(unit.distanceSymbol).frame(width: 44, alignment: .leading)
                Text("Pace").frame(width: 56, alignment: .leading)
                Spacer(minLength: 0)
                Text("Elev").frame(width: 52, alignment: .trailing)
            }
            .metricLabelStyle()

            ForEach(splits) { split in
                row(split, isFastest: split.id == fastest?.id)
            }
        }
        .padding(Space.x4)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private func row(_ split: Split, isFastest: Bool) -> some View {
        let pace = split.pace(in: unit)
        let fraction = barFraction(for: pace)
        return HStack(spacing: Space.x3) {
            Text(split.isPartial(in: unit)
                 ? RunFormat.distance(split.distance, unit: unit)
                 : "\(split.index)")
                .frame(width: 44, alignment: .leading)
            Text(RunFormat.pace(pace))
                .fontWeight(isFastest ? .bold : .regular)
                .foregroundStyle(isFastest ? Color.track : Color.ink)
                .frame(width: 56, alignment: .leading)
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: Radius.sm)
                    .fill(isFastest ? Color.track : Color.lane)
                    .frame(width: geo.size.width * fraction)
            }
            .frame(height: 12)
            Text(RunFormat.elevationDelta(split.elevationDelta, unit: unit))
                .font(.caption)
                .foregroundStyle(.inkMuted)
                .frame(width: 52, alignment: .trailing)
        }
        .font(.subheadline)
        .monospacedDigit()
        .foregroundStyle(.ink)
        .accessibilityElement(children: .combine)
    }
}
