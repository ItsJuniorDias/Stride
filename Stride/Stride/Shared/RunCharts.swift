import SwiftUI
import Charts
import StrideKit
import StrideUI

typealias SeriesPoint = RouteAnalysis.SeriesPoint

/// A titled chart on a raised card. While scrubbing, the summary shows the value under the finger.
struct ChartCard<Content: View>: View {
    let title: String
    let summary: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.headline).foregroundStyle(.ink)
                Spacer()
                Text(summary)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.inkMuted)
                    .contentTransition(.numericText())
            }
            content
        }
        .padding(Space.x4)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
    }
}

extension Array where Element == SeriesPoint {
    /// The point closest to a distance in meters.
    func nearest(to meters: Double?) -> SeriesPoint? {
        guard let meters else { return nil }
        return self.min { abs($0.distance - meters) < abs($1.distance - meters) }
    }
}

/// Stacked charts share one distance axis: the same x domain and the same y-label width,
/// so a selection lines up vertically across all of them.
private let yLabelWidth: CGFloat = 56

/// Binds a chart's x selection (in the runner's unit) to a shared selection in meters.
private func unitSelection(_ meters: Binding<Double?>, unit: UnitSystem) -> Binding<Double?> {
    Binding(
        get: { meters.wrappedValue.map { $0 / unit.metersPerUnit } },
        set: { meters.wrappedValue = $0.map { $0 * unit.metersPerUnit } }
    )
}

private func distanceAxis(unit: UnitSystem) -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 5)) { value in
        AxisGridLine().foregroundStyle(Color.line.opacity(0.6))
        AxisValueLabel {
            if let distance = value.as(Double.self) {
                Text("\(distance.formatted(.number.precision(.fractionLength(0...1)))) \(unit.distanceSymbol)")
            }
        }
    }
}

private func yLabel(_ text: String) -> some View {
    Text(text)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(width: yLabelWidth, alignment: .trailing)
}

private func pointLabel(_ point: SeriesPoint, unit: UnitSystem) -> String {
    "\(RunFormat.distance(point.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
}

// MARK: - Pace

/// Pace along the run, faster at the top, with the average as a dashed rule.
struct PaceChart: View {
    let series: [SeriesPoint]
    let unit: UnitSystem
    let average: Double?
    /// Distance axis in the runner's unit, shared with the other charts.
    let xDomain: ClosedRange<Double>
    @Binding var selection: Double?

    /// The middle 90% of paces plus the average, padded: one odd stretch can't flatten the rest.
    private var yDomain: ClosedRange<Double> {
        let sorted = series.map(\.value).sorted()
        guard let first = sorted.first else { return 0...1 }
        let low = Swift.min(sorted[Int(Double(sorted.count - 1) * 0.05)], average ?? first)
        let high = Swift.max(sorted[Int(Double(sorted.count - 1) * 0.95)], average ?? first)
        let padding = Swift.max((high - low) * 0.15, 5)
        return (low - padding)...(high + padding)
    }

    var body: some View {
        let domain = yDomain
        let selected = series.nearest(to: selection)
        Chart {
            ForEach(series) { point in
                LineMark(x: .value("Distance", point.distance / unit.metersPerUnit), y: .value("Pace", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.lane)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .accessibilityLabel(pointLabel(point, unit: unit))
                    .accessibilityValue("\(RunFormat.pace(point.value)) \(unit.paceSymbol)")
            }
            if let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Color.inkMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityLabel("Average pace")
                    .accessibilityValue("\(RunFormat.pace(average)) \(unit.paceSymbol)")
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.distance / unit.metersPerUnit))
                    .foregroundStyle(Color.lineStrong)
                    .accessibilityHidden(true)
                // Kept on the plot even when the selected pace is outside the trimmed domain.
                PointMark(x: .value("Distance", selected.distance / unit.metersPerUnit),
                          y: .value("Pace", Swift.min(Swift.max(selected.value, domain.lowerBound), domain.upperBound)))
                    .foregroundStyle(Color.lane)
                    .symbolSize(70)
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: .automatic(includesZero: false, reversed: true, dataType: Double.self) {
            $0 = [domain.lowerBound, domain.upperBound]
        })
        .chartPlotStyle { $0.clipped() }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.line.opacity(0.6))
                AxisValueLabel {
                    if let pace = value.as(Double.self) { yLabel(RunFormat.pace(pace)) }
                }
            }
        }
        .chartXAxis { distanceAxis(unit: unit) }
        .chartXSelection(value: unitSelection($selection, unit: unit))
        .frame(height: 180)
    }
}

// MARK: - Elevation

struct ElevationChart: View {
    let series: [SeriesPoint]
    let unit: UnitSystem
    let xDomain: ClosedRange<Double>
    @Binding var selection: Double?

    var body: some View {
        let values = series.map { unit.elevation(fromMeters: $0.value) }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = Swift.max((high - low) * 0.2, 5)
        let base = low - padding
        let selected = series.nearest(to: selection)
        Chart {
            ForEach(series) { point in
                AreaMark(
                    x: .value("Distance", point.distance / unit.metersPerUnit),
                    yStart: .value("Base", base),
                    yEnd: .value("Elevation", unit.elevation(fromMeters: point.value))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(LinearGradient(colors: [Color.lineStrong.opacity(0.35), Color.lineStrong.opacity(0.05)],
                                                startPoint: .top, endPoint: .bottom))
                .accessibilityHidden(true)
                LineMark(x: .value("Distance", point.distance / unit.metersPerUnit),
                         y: .value("Elevation", unit.elevation(fromMeters: point.value)))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.inkMuted)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                    .accessibilityLabel(pointLabel(point, unit: unit))
                    .accessibilityValue("\(Int(unit.elevation(fromMeters: point.value))) \(unit.elevationSymbol)")
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.distance / unit.metersPerUnit))
                    .foregroundStyle(Color.lineStrong)
                    .accessibilityHidden(true)
                PointMark(x: .value("Distance", selected.distance / unit.metersPerUnit),
                          y: .value("Elevation", unit.elevation(fromMeters: selected.value)))
                    .foregroundStyle(Color.ink)
                    .symbolSize(60)
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: base...(high + padding))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Color.line.opacity(0.6))
                AxisValueLabel {
                    if let altitude = value.as(Double.self) { yLabel("\(Int(altitude)) \(unit.elevationSymbol)") }
                }
            }
        }
        .chartXAxis { distanceAxis(unit: unit) }
        .chartXSelection(value: unitSelection($selection, unit: unit))
        .frame(height: 140)
    }
}

// MARK: - Heart rate

/// Heart rate along the run. The line takes each zone's color where it passes through that zone.
struct HeartRateChart: View {
    let series: [SeriesPoint]
    let unit: UnitSystem
    let maxHeartRate: Double
    let xDomain: ClosedRange<Double>
    @Binding var selection: Double?

    var body: some View {
        let gradient = zoneGradient
        let selected = series.nearest(to: selection)
        Chart {
            ForEach(series) { point in
                LineMark(x: .value("Distance", point.distance / unit.metersPerUnit), y: .value("Heart rate", point.value))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(gradient)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .accessibilityLabel(pointLabel(point, unit: unit))
                    .accessibilityValue("\(Int(point.value)) bpm")
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.distance / unit.metersPerUnit))
                    .foregroundStyle(Color.lineStrong)
                    .accessibilityHidden(true)
                PointMark(x: .value("Distance", selected.distance / unit.metersPerUnit), y: .value("Heart rate", selected.value))
                    .foregroundStyle(color(for: selected.value))
                    .symbolSize(70)
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: xDomain)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(Color.line.opacity(0.6))
                AxisValueLabel {
                    if let bpm = value.as(Double.self) { yLabel("\(Int(bpm))") }
                }
            }
        }
        .chartXAxis { distanceAxis(unit: unit) }
        .chartXSelection(value: unitSelection($selection, unit: unit))
        .frame(height: 160)
    }

    private func color(for bpm: Double) -> Color {
        (HeartRateZone.zone(for: bpm, maxHeartRate: maxHeartRate) ?? .recovery).color
    }

    /// Hard color stops at the zone boundaries, positioned over the line's own vertical extent.
    private var zoneGradient: LinearGradient {
        let values = series.map(\.value)
        guard let low = values.min(), let high = values.max(), high > low else {
            return LinearGradient(colors: [color(for: values.first ?? 0)], startPoint: .bottom, endPoint: .top)
        }
        var stops = [Gradient.Stop(color: color(for: low), location: 0)]
        for zone in HeartRateZone.allCases {
            let boundary = zone.lowerBound * maxHeartRate
            guard boundary > low, boundary < high else { continue }
            let location = (boundary - low) / (high - low)
            stops.append(Gradient.Stop(color: color(for: boundary - 0.01), location: location))
            stops.append(Gradient.Stop(color: zone.color, location: location))
        }
        // Close with the band the line ends in, so a maximum exactly on a boundary doesn't blend two zones.
        stops.append(Gradient.Stop(color: stops[stops.count - 1].color, location: 1))
        return LinearGradient(stops: stops, startPoint: .bottom, endPoint: .top)
    }
}
