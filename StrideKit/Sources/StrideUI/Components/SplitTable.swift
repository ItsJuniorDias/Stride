import SwiftUI
import StrideKit

/// Per-unit splits with a speed bar. The fastest full split is the only highlight.
public struct SplitTable: View {
    let splits: [Split]
    let unit: UnitSystem

    public init(splits: [Split], unit: UnitSystem) {
        self.splits = splits
        self.unit = unit
    }

    private var fastestPace: Double? {
        Split.fastest(in: splits, unit: unit)?.pace(in: unit)
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
        let relative = (fastestPace.flatMap { fastest in pace.map { fastest / $0 } }) ?? 0
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
                    .frame(width: geo.size.width * min(max(relative, 0.4), 1))
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
