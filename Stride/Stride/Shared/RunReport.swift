import SwiftUI
import StrideKit
import StrideUI

/// Map, distance, metrics, splits and heart-rate zones for a finished run, stacked. The run detail
/// screen lays out the same pieces itself (below), with its record card and charts between them.
struct RunReport: View {
    let run: Run
    let route: [RoutePoint]
    let splits: [Split]
    let unit: UnitSystem
    /// Heart rate, when this device has it.
    var vitals: RunVitals?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x4) {
            if route.count > 1 {
                RouteMapView(points: route)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .accessibilityLabel("Route map, colored by pace")
            }

            RunDistanceHero(distance: run.distance, unit: unit)

            RunMetricsGrid(run: run, splits: splits, unit: unit, averageHeartRate: vitals?.averageHeartRate)

            if !splits.isEmpty {
                RunSplitsCard(splits: splits, unit: unit, averagePace: run.averagePace(in: unit))
            }

            let zones = vitals?.zoneSeconds ?? [:]
            if !zones.isEmpty {
                RunZonesCard(seconds: zones, averageHeartRate: vitals?.averageHeartRate)
            }
        }
    }
}

// MARK: - Distance

/// "DISTANCE" over the distance in 88pt SF Pro Expanded, the unit beside it.
struct RunDistanceHero: View {
    let distance: Double
    let unit: UnitSystem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Distance").metricLabelStyle()
            HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                Text(RunFormat.distance(distance, unit: unit))
                    .font(.metricHero)
                    .monospacedDigit()
                    .tracking(-1.76)
                    .foregroundStyle(.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text(unit.distanceSymbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.inkMuted)
                    .fixedSize()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Distance")
        .accessibilityValue(CoachScript.spokenDistance(distance, unit: unit))
    }
}

// MARK: - Metrics

/// The run's numbers in three columns on a raised card: time, pace, heart rate, climb, calories and
/// the fastest split. A trophy marks a metric that holds a personal record.
struct RunMetricsGrid: View {
    let run: Run
    let splits: [Split]
    let unit: UnitSystem
    var averageHeartRate: Double?
    /// Records this run set and still holds; ``RecordKind/longestDuration`` and
    /// ``RecordKind/mostElevation`` put a trophy on Time and Elevation.
    var records: Set<RecordKind> = []

    private struct Tile: Identifiable {
        let label: String
        let value: String
        var unit: String?
        var isRecord = false
        let spokenLabel: String
        let spokenValue: String
        var id: String { label }
    }

    private var tiles: [Tile] {
        let unitName = unit == .metric ? "kilometer" : "mile"
        var tiles = [
            Tile(label: "Time", value: RunFormat.duration(run.duration), isRecord: records.contains(.longestDuration),
                 spokenLabel: "Time", spokenValue: CoachScript.spokenDuration(run.duration)),
            Tile(label: "Avg pace", value: RunFormat.pace(run.averagePace(in: unit)), unit: unit.paceSymbol,
                 spokenLabel: "Average pace",
                 spokenValue: run.averagePace(in: unit).map { CoachScript.spokenPace($0, unit: unit) } ?? "Not available"),
        ]
        if let averageHeartRate {
            tiles.append(Tile(label: "Avg HR", value: "\(Int(averageHeartRate.rounded()))", unit: "bpm",
                              spokenLabel: "Average heart rate", spokenValue: "\(Int(averageHeartRate.rounded())) beats per minute"))
        }
        let climb = Int(unit.elevation(fromMeters: run.elevationGain).rounded())
        tiles.append(Tile(label: "Elevation", value: "\(climb)", unit: unit.elevationSymbol,
                          isRecord: records.contains(.mostElevation), spokenLabel: "Elevation gain",
                          spokenValue: "\(climb) \(unit == .metric ? "meters" : "feet")"))
        tiles.append(Tile(label: "Calories", value: "\(Int(run.calories.rounded()))", unit: "kcal",
                          spokenLabel: "Calories", spokenValue: "\(Int(run.calories.rounded())) kilocalories"))
        if let fastest = Split.fastest(in: splits, unit: unit), let pace = fastest.pace(in: unit) {
            tiles.append(Tile(label: "Fastest \(unit.distanceSymbol)", value: RunFormat.pace(pace), unit: unit.paceSymbol,
                              spokenLabel: "Fastest \(unitName)", spokenValue: CoachScript.spokenPace(pace, unit: unit)))
        }
        return tiles
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Space.x3, alignment: .topLeading), count: 3),
                  alignment: .leading, spacing: 14) {
            ForEach(tiles) { tile in
                StatTile(tile.label, value: tile.value, unit: tile.unit, symbol: tile.isRecord ? .record : nil)
                    .accessibilityLabel(tile.spokenLabel)
                    .accessibilityValue(tile.isRecord ? "\(tile.spokenValue), personal record" : tile.spokenValue)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
    }
}

// MARK: - Splits

/// Per kilometer or mile: pace (the fastest in bold), a bar in the pace color scaled from the
/// slowest split (40%) to the fastest (100%), the climb, and the average heart rate when there is one.
struct RunSplitsCard: View {
    let splits: [Split]
    let unit: UnitSystem
    let averagePace: Double?
    /// Heart rate along the route, averaged per split; empty leaves the column out.
    var heartRate: [SeriesPoint] = []

    var body: some View {
        let fastest = Split.fastest(in: splits, unit: unit)
        let heartRates = splitHeartRates
        let showsHeartRate = heartRates.contains { $0 != nil }
        let indexWidth: CGFloat = splits.contains { $0.isPartial(in: unit) } ? 30 : 22
        VStack(alignment: .leading, spacing: Space.x1) {
            SectionHeading("Splits", caption: "Avg \(RunFormat.pace(averagePace)) \(unit.paceSymbol)")
                .padding(.bottom, 6)

            HStack(spacing: 10) {
                Text(unit.distanceSymbol.capitalized).frame(width: indexWidth, alignment: .leading)
                Text("Pace").frame(width: 54, alignment: .leading)
                Spacer(minLength: 0)
                Text("Elev").frame(width: 50, alignment: .trailing)
                if showsHeartRate {
                    Text("HR").frame(width: 30, alignment: .trailing)
                }
            }
            .metricLabelStyle()
            .padding(.bottom, 2)
            .accessibilityHidden(true)

            ForEach(Array(splits.enumerated()), id: \.element.id) { index, split in
                row(split, isFastest: split.id == fastest?.id, heartRate: heartRates[index],
                    showsHeartRate: showsHeartRate, indexWidth: indexWidth)
            }
        }
        .raisedCard()
    }

    private func row(_ split: Split, isFastest: Bool, heartRate: Double?, showsHeartRate: Bool,
                     indexWidth: CGFloat) -> some View {
        let pace = split.pace(in: unit)
        return HStack(spacing: 10) {
            Text(label(for: split))
                .foregroundStyle(.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: indexWidth, alignment: .leading)
            Text(RunFormat.pace(pace))
                .fontWeight(isFastest ? .bold : .regular)
                .foregroundStyle(.ink)
                .frame(width: 54, alignment: .leading)
            TrackBar(progress: barFraction(for: pace), tint: PaceScale.color(pace: pace, average: averagePace), height: 10)
            Text(RunFormat.elevationDelta(split.elevationDelta, unit: unit))
                .foregroundStyle(.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: 50, alignment: .trailing)
            if showsHeartRate {
                Text(heartRate.map { "\(Int($0.rounded()))" } ?? RunFormat.empty)
                    .foregroundStyle(.ink)
                    .frame(width: 30, alignment: .trailing)
            }
        }
        .font(.subheadline)
        .monospacedDigit()
        .frame(minHeight: 24)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel(for: split))
        .accessibilityValue(spokenValue(split, pace: pace, isFastest: isFastest, heartRate: heartRate))
    }

    /// "3", or "0.8" for the partial split at the end.
    private func label(for split: Split) -> String {
        guard split.isPartial(in: unit) else { return "\(split.index)" }
        return (split.distance / unit.metersPerUnit).formatted(.number.precision(.fractionLength(1...2)))
    }

    private func spokenLabel(for split: Split) -> String {
        let name = unit == .metric ? "Kilometer" : "Mile"
        return split.isPartial(in: unit)
            ? "Last \(CoachScript.spokenDistance(split.distance, unit: unit))"
            : "\(name) \(split.index)"
    }

    private func spokenValue(_ split: Split, pace: Double?, isFastest: Bool, heartRate: Double?) -> String {
        var parts = [pace.map { CoachScript.spokenPace($0, unit: unit) } ?? "No pace"]
        let climb = Int(unit.elevation(fromMeters: split.elevationDelta).rounded())
        let unitName = unit == .metric ? "meters" : "feet"
        if climb > 0 { parts.append("up \(climb) \(unitName)") }
        if climb < 0 { parts.append("down \(-climb) \(unitName)") }
        if let heartRate { parts.append("\(Int(heartRate.rounded())) beats per minute") }
        if isFastest { parts.append("fastest") }
        return parts.joined(separator: ", ")
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

    /// The average of the heart-rate series within each split's stretch of the route.
    private var splitHeartRates: [Double?] {
        guard !heartRate.isEmpty else { return splits.map { _ in nil } }
        var start = 0.0
        return splits.map { split in
            let end = start + split.distance
            let inside = heartRate.filter { $0.distance > start && $0.distance <= end }
            start = end
            guard !inside.isEmpty else { return nil }
            return inside.reduce(0) { $0 + $1.value } / Double(inside.count)
        }
    }
}

// MARK: - Heart-rate zones

/// Time in each zone, highest on top, with the run's average and maximum heart rate beside the title.
struct RunZonesCard: View {
    let seconds: [HeartRateZone: TimeInterval]
    var averageHeartRate: Double?
    var maxHeartRate: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let caption {
                SectionHeading("Heart rate zones", caption: caption)
            } else {
                SectionHeading("Heart rate zones")
            }
            ZoneTimeList(seconds: seconds)
        }
        .raisedCard()
    }

    /// "Avg 152 · max 181 bpm".
    private var caption: String? {
        let average = averageHeartRate.map { Int($0.rounded()) }
        let maximum = maxHeartRate.map { Int($0.rounded()) }
        switch (average, maximum) {
        case let (average?, maximum?): return "Avg \(average) · max \(maximum) bpm"
        case let (average?, nil): return "Avg \(average) bpm"
        case let (nil, maximum?): return "Max \(maximum) bpm"
        case (nil, nil): return nil
        }
    }
}
