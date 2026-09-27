import SwiftUI
import Charts
import StrideKit
import StrideUI

typealias SeriesPoint = RouteAnalysis.SeriesPoint

/// A titled chart on a raised card: the 17pt title with a muted caption at the trailing end, which
/// can show the value under the finger while scrubbing.
struct ChartCard<Content: View>: View {
    let title: String
    let summary: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            SectionHeading(title) {
                Text(summary)
                    .font(.footnote.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.inkMuted)
                    .contentTransition(.numericText())
            }
            content
        }
        .raisedCard()
    }
}

extension Array where Element == SeriesPoint {
    /// The point closest to a distance in meters.
    func nearest(to meters: Double?) -> SeriesPoint? {
        guard let meters else { return nil }
        return self.min { abs($0.distance - meters) < abs($1.distance - meters) }
    }
}

/// Binds a chart's x selection (in the runner's unit) to a shared selection in meters.
private func unitSelection(_ meters: Binding<Double?>, unit: UnitSystem) -> Binding<Double?> {
    Binding(
        get: { meters.wrappedValue.map { $0 / unit.metersPerUnit } },
        set: { meters.wrappedValue = $0.map { $0 * unit.metersPerUnit } }
    )
}

private func pointLabel(_ point: SeriesPoint, unit: UnitSystem) -> String {
    "\(RunFormat.distance(point.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
}

// MARK: - Along the route

/// Run detail: pace with the elevation profile behind it, then heart rate colored by zone, over one
/// distance axis. Scrubbing either chart moves one selection across both, and the values above
/// them follow it ("At 2.5 km"); letting go shows the whole run again. Parts without data are left
/// out; show the card only when at least one series has three points.
struct RouteChartsCard: View {
    let pace: [SeriesPoint]
    let elevation: [SeriesPoint]
    let heartRate: [SeriesPoint]
    let unit: UnitSystem
    let averagePace: Double?
    /// Meters climbed over the run.
    let elevationGain: Double
    let averageHeartRate: Double?
    let maxHeartRate: Double

    /// Meters along the route under the finger.
    @State private var selection: Double?

    /// Axis labels sit in a fixed column, so both plots start at the same x and a selection lines up.
    private static let axisWidth: CGFloat = 34
    private static let axisGap: CGFloat = 6
    private static var plotInset: CGFloat { axisWidth + axisGap }

    static func hasContent(pace: [SeriesPoint], elevation: [SeriesPoint], heartRate: [SeriesPoint]) -> Bool {
        pace.count > 2 || elevation.count > 2 || heartRate.count > 2
    }

    private var hasPace: Bool { pace.count > 2 }
    private var hasElevation: Bool { elevation.count > 2 }
    private var hasHeartRate: Bool { heartRate.count > 2 }

    var body: some View {
        let domain = xDomain
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading("Along the route") {
                Text(scope)
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(selection == nil ? Color.inkMuted : Color.lane)
                    .contentTransition(.numericText())
            }
            if hasPace || hasElevation {
                if hasPace {
                    legendRow("Pace", swatch: Color.lane, value: paceValue)
                        .padding(.top, 10)
                }
                paceChart(domain)
                    .frame(height: 96)
                    .padding(.top, hasPace ? Space.x2 : 10)
            }
            if hasHeartRate {
                legendRow("Heart rate", swatch: PaceScale.gradient, value: heartRateValue)
                    .padding(.top, hasPace || hasElevation ? Space.x3 : 10)
                heartRateChart(domain)
                    .frame(height: 64)
                    .padding(.top, Space.x2)
            }
            distanceLabels(domain)
                .padding(.top, 6)
        }
        .raisedCard()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pace, elevation and heart rate along the route")
        .sensoryFeedback(.selection, trigger: selection == nil)
    }

    /// One distance axis in the runner's unit for all the charts.
    private var xDomain: ClosedRange<Double> {
        let end = [pace.last, elevation.last, heartRate.last].compactMap { $0?.distance }.max() ?? 0
        return 0...Swift.max(end / unit.metersPerUnit, 0.1)
    }

    // MARK: Values above the charts

    /// "Whole run", or "At 2.5 km" while scrubbing.
    private var scope: String {
        guard let selection else { return "Whole run" }
        return "At \(RunFormat.distance(selection, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
    }

    private var paceValue: String {
        if let point = pace.nearest(to: selection) {
            return "\(RunFormat.pace(point.value)) \(unit.paceSymbol)"
        }
        return "Avg \(RunFormat.pace(averagePace)) \(unit.paceSymbol)"
    }

    private var elevationValue: String {
        if let point = elevation.nearest(to: selection) {
            return "\(Int(unit.elevation(fromMeters: point.value).rounded())) \(unit.elevationSymbol)"
        }
        return "+\(Int(unit.elevation(fromMeters: elevationGain).rounded())) \(unit.elevationSymbol)"
    }

    private var heartRateValue: String {
        if let point = heartRate.nearest(to: selection) {
            let bpm = "\(Int(point.value.rounded())) bpm"
            guard let zone = HeartRateZone.zone(for: point.value, maxHeartRate: maxHeartRate) else { return bpm }
            return "\(bpm) · Zone \(zone.rawValue)"
        }
        let total = heartRate.reduce(0.0) { $0 + $1.value }
        let average = averageHeartRate ?? total / Double(Swift.max(heartRate.count, 1))
        return "Avg \(Int(average.rounded())) bpm"
    }

    private func legendRow(_ title: String, swatch: some ShapeStyle, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
            HStack(spacing: 5) {
                Capsule().fill(swatch).frame(width: 12, height: 3)
                Text(title).metricLabelStyle()
            }
            Spacer(minLength: Space.x2)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(.ink)
                .contentTransition(.numericText())
                .lineLimit(1)
        }
        .padding(.leading, Self.plotInset)
    }

    // MARK: Pace and elevation

    private func paceChart(_ domain: ClosedRange<Double>) -> some View {
        let axis = PaceAxis(series: pace, average: averagePace)
        return HStack(spacing: Self.axisGap) {
            AxisLabels(ticks: hasPace ? axis.ticks.map { (value: $0, text: RunFormat.pace($0)) } : [],
                       domain: axis.lower...axis.upper, higherIsUp: false)
                .frame(width: Self.axisWidth)
            ZStack(alignment: .bottomTrailing) {
                if hasElevation {
                    elevationBackdrop(domain)
                        .allowsHitTesting(false)
                }
                if hasPace {
                    paceLine(domain, axis: axis)
                }
                if hasElevation {
                    HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                        Text("Elevation").metricLabelStyle()
                        Text(elevationValue)
                            .font(.caption2.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.ink)
                            .contentTransition(.numericText())
                    }
                    .padding(.trailing, 6)
                    .padding(.bottom, 5)
                    .allowsHitTesting(false)
                }
            }
        }
    }

    private func paceLine(_ domain: ClosedRange<Double>, axis: PaceAxis) -> some View {
        let selected = pace.nearest(to: selection)
        let lower = axis.lower, upper = axis.upper
        return Chart {
            ForEach(axis.ticks, id: \.self) { tick in
                RuleMark(y: .value("Grid", tick))
                    .foregroundStyle(Color.line.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .accessibilityHidden(true)
            }
            if let averagePace {
                RuleMark(y: .value("Average", axis.clamp(averagePace)))
                    .foregroundStyle(Color.inkMuted)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .accessibilityLabel("Average pace")
                    .accessibilityValue("\(RunFormat.pace(averagePace)) \(unit.paceSymbol)")
            }
            ForEach(pace) { point in
                // Kept inside the axis, so one odd stretch can't run off the card.
                LineMark(x: .value("Distance", point.distance / unit.metersPerUnit), y: .value("Pace", axis.clamp(point.value)))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(Color.lane)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .accessibilityLabel(pointLabel(point, unit: unit))
                    .accessibilityValue("\(RunFormat.pace(point.value)) \(unit.paceSymbol)")
            }
            if let selected {
                RuleMark(x: .value("Selected", selected.distance / unit.metersPerUnit))
                    .foregroundStyle(Color.lineStrong)
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .accessibilityHidden(true)
                PointMark(x: .value("Distance", selected.distance / unit.metersPerUnit), y: .value("Pace", axis.clamp(selected.value)))
                    .foregroundStyle(Color.surfaceRaised)
                    .symbolSize(160)
                    .accessibilityHidden(true)
                PointMark(x: .value("Distance", selected.distance / unit.metersPerUnit), y: .value("Pace", axis.clamp(selected.value)))
                    .foregroundStyle(Color.lane)
                    .symbolSize(80)
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: domain)
        // Faster at the top.
        .chartYScale(domain: .automatic(includesZero: false, reversed: true, dataType: Double.self) {
            $0 = [lower, upper]
        })
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartXSelection(value: unitSelection($selection, unit: unit))
    }

    /// The elevation profile as a soft muted area in the lower part of the pace chart.
    private func elevationBackdrop(_ domain: ClosedRange<Double>) -> some View {
        let values = elevation.map { unit.elevation(fromMeters: $0.value) }
        let low = values.min() ?? 0, high = values.max() ?? 1
        let range = Swift.max(high - low, 10)
        let base = low - range * 0.17
        let fill = LinearGradient(colors: [Color.inkMuted.opacity(0.34), Color.inkMuted.opacity(0.06)],
                                  startPoint: .top, endPoint: .bottom)
        return Chart {
            ForEach(elevation) { point in
                AreaMark(
                    x: .value("Distance", point.distance / unit.metersPerUnit),
                    yStart: .value("Base", base),
                    yEnd: .value("Elevation", unit.elevation(fromMeters: point.value))
                )
                .interpolationMethod(.catmullRom)
                .foregroundStyle(fill)
                .accessibilityLabel(pointLabel(point, unit: unit))
                .accessibilityValue("Elevation \(Int(unit.elevation(fromMeters: point.value).rounded())) \(unit.elevationSymbol)")
            }
        }
        .chartXScale(domain: domain)
        .chartYScale(domain: base...(high + range * 0.42))
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
    }

    // MARK: Heart rate

    private func heartRateChart(_ domain: ClosedRange<Double>) -> some View {
        let values = heartRate.map(\.value)
        let low = values.min() ?? 0, high = values.max() ?? 1
        let padding = Swift.max((high - low) * 0.12, 4)
        let yDomain = (low - padding)...(high + padding)
        // Zone boundaries inside the range, as dashed rules labeled in bpm.
        let boundaries = HeartRateZone.allCases.map { $0.lowerBound * maxHeartRate }
            .filter { $0 > yDomain.lowerBound && $0 < yDomain.upperBound }
        let selected = heartRate.nearest(to: selection)
        let gradient = zoneGradient
        return HStack(spacing: Self.axisGap) {
            AxisLabels(ticks: boundaries.map { (value: $0, text: "\(Int($0.rounded()))") }, domain: yDomain, higherIsUp: true)
                .frame(width: Self.axisWidth)
            Chart {
                ForEach(boundaries, id: \.self) { boundary in
                    RuleMark(y: .value("Zone boundary", boundary))
                        .foregroundStyle(Color.line.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 4]))
                        .accessibilityHidden(true)
                }
                ForEach(heartRate) { point in
                    LineMark(x: .value("Distance", point.distance / unit.metersPerUnit), y: .value("Heart rate", point.value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(gradient)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .accessibilityLabel(pointLabel(point, unit: unit))
                        .accessibilityValue("\(Int(point.value.rounded())) bpm")
                }
                if let selected {
                    RuleMark(x: .value("Selected", selected.distance / unit.metersPerUnit))
                        .foregroundStyle(Color.lineStrong)
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .accessibilityHidden(true)
                    PointMark(x: .value("Distance", selected.distance / unit.metersPerUnit), y: .value("Heart rate", selected.value))
                        .foregroundStyle(Color.surfaceRaised)
                        .symbolSize(160)
                        .accessibilityHidden(true)
                    PointMark(x: .value("Distance", selected.distance / unit.metersPerUnit), y: .value("Heart rate", selected.value))
                        .foregroundStyle(color(for: selected.value))
                        .symbolSize(80)
                        .accessibilityHidden(true)
                }
            }
            .chartXScale(domain: domain)
            .chartYScale(domain: yDomain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartXSelection(value: unitSelection($selection, unit: unit))
        }
    }

    private func color(for bpm: Double) -> Color {
        (HeartRateZone.zone(for: bpm, maxHeartRate: maxHeartRate) ?? .recovery).color
    }

    /// Hard color stops at the zone boundaries, positioned over the line's own vertical extent.
    private var zoneGradient: LinearGradient {
        let values = heartRate.map(\.value)
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

    // MARK: Distance axis

    /// "0 1 2 3 4" under the plots and the full distance with its unit at the end.
    private func distanceLabels(_ domain: ClosedRange<Double>) -> some View {
        let end = domain.upperBound
        let step = Self.labelStep(for: end)
        let ticks = Array(stride(from: 0, through: end - step * 0.6, by: step))
        return GeometryReader { geo in
            let width = Swift.max(geo.size.width - Self.plotInset, 1)
            ZStack(alignment: .topTrailing) {
                ForEach(ticks, id: \.self) { tick in
                    Text(tick.formatted(.number.precision(.fractionLength(0...1))))
                        .fixedSize()
                        .position(x: Self.plotInset + width * tick / end, y: 8)
                }
                Text("\(end.formatted(.number.precision(.fractionLength(0...1)))) \(unit.distanceSymbol)")
                    .fixedSize()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .font(.caption2.weight(.medium))
        .monospacedDigit()
        .foregroundStyle(.inkMuted)
        .frame(height: 16)
        .accessibilityHidden(true)
    }

    private static func labelStep(for end: Double) -> Double {
        switch end {
        case ..<1.2: 0.2
        case ..<3: 0.5
        case ..<7: 1
        case ..<13: 2
        case ..<30: 5
        case ..<70: 10
        default: 20
        }
    }
}

/// Four evenly spaced pace ticks on round values, covering the middle 90% of the run's paces and
/// its average: the axis of the pace chart.
private struct PaceAxis {
    let ticks: [Double]
    var lower: Double { ticks.first ?? 0 }
    var upper: Double { ticks.last ?? 1 }

    init(series: [SeriesPoint], average: Double?) {
        let sorted = series.map(\.value).sorted()
        guard let first = sorted.first else {
            ticks = [0, 1]
            return
        }
        var low = Swift.min(sorted[Int(Double(sorted.count - 1) * 0.05)], average ?? first)
        var high = Swift.max(sorted[Int(Double(sorted.count - 1) * 0.95)], average ?? first)
        let padding = Swift.max((high - low) * 0.08, 3)
        low -= padding
        high += padding
        // Seconds per unit: 5 s up to 15 min between ticks.
        let steps: [Double] = [5, 10, 15, 20, 30, 45, 60, 90, 120, 180, 300, 600, 900]
        var chosen = (step: steps[steps.count - 1], start: (low / steps[steps.count - 1]).rounded(.down) * steps[steps.count - 1])
        for step in steps {
            let start = (low / step).rounded(.down) * step
            if start + 3 * step >= high {
                chosen = (step: step, start: start)
                break
            }
        }
        ticks = (0...3).map { chosen.start + Double($0) * chosen.step }
    }

    func clamp(_ value: Double) -> Double {
        Swift.min(Swift.max(value, lower), upper)
    }
}

/// Labels in a fixed-width column beside a plot, each centered on its value's height.
private struct AxisLabels: View {
    let ticks: [(value: Double, text: String)]
    let domain: ClosedRange<Double>
    /// Heart rate: higher values higher up. Pace: faster (lower) values higher up.
    let higherIsUp: Bool

    var body: some View {
        GeometryReader { geo in
            let span = Swift.max(domain.upperBound - domain.lowerBound, .leastNonzeroMagnitude)
            ForEach(ticks.indices, id: \.self) { index in
                let tick = ticks[index]
                let fraction = (tick.value - domain.lowerBound) / span
                Text(tick.text)
                    .font(.caption2.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(.inkMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: geo.size.width, alignment: .trailing)
                    .position(x: geo.size.width / 2, y: geo.size.height * (higherIsUp ? 1 - fraction : fraction))
            }
        }
        .accessibilityHidden(true)
    }
}
