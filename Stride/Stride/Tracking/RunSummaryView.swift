import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// Shown right after a run is finished. The run is already saved; this screen adds how it felt.
struct RunSummaryView: View {
    @Bindable var run: Run
    /// Records this run set; passed in so they stay while the cover slides away after the tracker resets.
    let achievements: [RecordAchievement]
    @Environment(RunTracker.self) private var tracker
    @Environment(\.modelContext) private var context
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @State private var route: [RoutePoint] = []
    @State private var splits: [Split] = []
    /// Heart rate, when this device has it.
    @State private var vitals: RunVitals?
    /// Weeks in a row with a run, this one included.
    @State private var streakWeeks = 0
    @State private var confirmingDiscard = false
    @State private var sharing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header

                headlineMetrics
                    .padding(.top, Space.x5)

                detailGrid
                    .padding(.top, Space.x4)

                if route.count > 1 {
                    routeMap
                        .padding(.top, Space.x4)
                }

                if !achievements.isEmpty {
                    RecordEarnedCard(achievements: achievements, unit: unit)
                        .padding(.top, Space.x4)
                }

                if !splits.isEmpty {
                    splitsSection
                        .padding(.top, Space.x5)
                }

                if !zones.isEmpty {
                    VStack(alignment: .leading, spacing: Space.x3) {
                        SectionHeading("Heart rate zones")
                        ZoneShareCard(seconds: zones)
                    }
                    .padding(.top, Space.x5)
                }

                VStack(alignment: .leading, spacing: Space.x3) {
                    SectionHeading("How did it feel?")
                    FeelingPicker(selection: $run.feeling)
                }
                .padding(.top, Space.x5)

                VStack(alignment: .leading, spacing: Space.x2) {
                    SectionHeading("Surface")
                    SurfacePicker(selection: $run.surface)
                }
                .padding(.top, Space.x5)

                VStack(alignment: .leading, spacing: Space.x3) {
                    SectionHeading("Notes")
                    TextField("How did it go?", text: $run.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .foregroundStyle(.ink)
                        .padding(.vertical, 14)
                        .padding(.horizontal, Space.x4)
                        .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                }
                .padding(.top, 20)

                if let shoe = run.shoe {
                    ShoeWearRow(shoe: shoe, unit: unit)
                        .padding(.vertical, 14)
                        .padding(.horizontal, Space.x4)
                        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                        .padding(.top, Space.x4)
                    if shoe.isWornOut, !shoe.isRetired {
                        ShoeWearNotice(shoe: shoe, unit: unit)
                            .padding(.top, Space.x3)
                    }
                }
            }
            .padding(.horizontal, Space.x4)
            .padding(.top, Space.x2)
            .padding(.bottom, Space.x5)
            // In the content, so the glow scrolls away with the header.
            .background(alignment: .topLeading) {
                BrandGlow(.corner)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.surface)
        .safeAreaInset(edge: .bottom) {
            actionBar
        }
        .sheet(isPresented: $sharing) {
            ShareRunSheet(share: ShareRun(run: run, unit: unit))
        }
        .confirmationDialog("Discard this run?", isPresented: $confirmingDiscard, titleVisibility: .visible) {
            Button("Discard Run", role: .destructive) {
                // Deleted by RootView once the cover is gone, so this screen never shows a deleted run.
                tracker.discardSaved(run)
            }
        } message: {
            Text("It will be deleted and won't count toward your stats.")
        }
        .task(id: unit) {
            if route.isEmpty { route = run.route }
            splits = unit == .metric ? run.splits : RouteAnalysis.splits(from: route, unit: unit)
        }
        .task {
            vitals = Vitals.of(run.id, in: context)
            var descriptor = FetchDescriptor<Run>()
            descriptor.propertiesToFetch = [\.startDate]
            let dates = ((try? context.fetch(descriptor)) ?? []).map(\.startDate)
            streakWeeks = Streaks.summary(of: dates).currentWeeks
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                IconBadge("checkmark", style: .tinted(.success), size: 32)
                Spacer()
                Button { confirmingDiscard = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "trash")
                            .font(.system(size: 17))
                            .accessibilityHidden(true)
                        Text("Discard")
                    }
                    .font(.body)
                    .foregroundStyle(.danger)
                    .padding(.leading, Space.x3)
                    .padding(.trailing, Space.x1)
                    .frame(minHeight: Dimension.hitMin)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Discard run")
            }
            .frame(height: Dimension.hitMin)
            .padding(.vertical, Space.x1)

            Text("Run complete")
                .font(.largeTitle.bold())
                .tracking(-0.3)
                .foregroundStyle(.ink)
                .accessibilityAddTraits(.isHeader)
            Text("\(run.title) · \(run.startDate.formatted(.dateTime.weekday(.wide).day().month(.wide).hour().minute()))")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .padding(.top, Space.x1)

            if streakWeeks >= 2 {
                HStack(spacing: 10) {
                    ArtThumbnail(name: "streakFlame", width: 28, height: 28, cornerRadius: 14)
                    Text("\(streakWeeks)-week streak kept")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.ink)
                }
                .padding(.leading, Space.x1)
                .padding(.trailing, 14)
                .frame(height: 36)
                .background(Color.surfaceRaised, in: Capsule())
                .accessibilityElement(children: .combine)
                .padding(.top, Space.x3)
            }
        }
    }

    // MARK: Metrics

    private var averageHeartRate: Double? { vitals?.averageHeartRate ?? run.averageHeartRate }
    private var zones: [HeartRateZone: TimeInterval] {
        (vitals?.zoneSeconds ?? [:]).filter { $0.value > 0 }
    }
    private var fastestSplit: Split? { Split.fastest(in: splits, unit: unit) }

    private var headlineMetrics: some View {
        HStack(alignment: .top, spacing: Space.x3) {
            StatTile("Distance", value: RunFormat.distance(run.distance, unit: unit), unit: unit.distanceSymbol, size: .large)
            StatTile("Time", value: RunFormat.duration(run.duration), size: .large)
        }
    }

    /// Pace, heart rate, calories and climbing. Without heart rate (an iPhone run), the fastest split.
    private var detailGrid: some View {
        DividedGrid(columns: 2) {
            StatTile("Avg pace", value: RunFormat.pace(run.averagePace(in: unit)), unit: unit.paceSymbol, size: .medium)
            if let averageHeartRate {
                StatTile("Avg heart rate", value: "\(Int(averageHeartRate))", unit: "bpm", size: .medium)
            } else if let fastestSplit {
                StatTile("Fastest \(unit.distanceSymbol)", value: RunFormat.pace(fastestSplit.pace(in: unit)),
                         unit: unit.paceSymbol, size: .medium)
            }
            StatTile("Calories", value: "\(Int(run.calories))", unit: "kcal", size: .medium)
            StatTile("Elevation", value: "\(Int(unit.elevation(fromMeters: run.elevationGain)))",
                     unit: unit.elevationSymbol, size: .medium)
        }
    }

    private var routeMap: some View {
        RouteMapView(points: route, interactive: false)
            .frame(height: 164)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(routeLabel)
            .overlay(alignment: .topLeading) {
                PaceScaleLegend(faster: "Fast", slower: "Slow")
                    .padding(Space.x2)
            }
    }

    /// "Route colored by pace, from 4'21" to 7'30" /km".
    private var routeLabel: String {
        let paces = splits.filter { !$0.isPartial(in: unit) }.compactMap { $0.pace(in: unit) }
        guard let fastest = paces.min(), let slowest = paces.max(), slowest > fastest else { return "Route colored by pace" }
        return "Route colored by pace, from \(RunFormat.pace(fastest)) to \(RunFormat.pace(slowest)) \(unit.paceSymbol)"
    }

    @ViewBuilder private var splitsSection: some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            if let fastestSplit {
                SectionHeading("Splits",
                               caption: "Fastest \(unit.distanceSymbol) \(RunFormat.pace(fastestSplit.pace(in: unit))) \(unit.paceSymbol)")
            } else {
                SectionHeading("Splits")
            }
            SplitBars(splits: splits, unit: unit, averagePace: run.averagePace(in: unit))
        }
    }

    // MARK: Actions

    private var actionBar: some View {
        GeometryReader { geo in
            HStack(spacing: Space.x3) {
                Button { sharing = true } label: {
                    Label("Share", systemImage: "camera")
                }
                .buttonStyle(.strideSecondary)
                .frame(width: max((geo.size.width - Space.x3) * 0.4, 0))
                .accessibilityLabel("Share to Instagram Stories")
                Button("Save run") {
                    try? context.save()
                    tracker.reset()
                }
                .buttonStyle(.stridePrimary)
            }
        }
        .frame(height: Dimension.control)
        .padding(.horizontal, Space.x4)
        .padding(.top, Space.x3)
        .padding(.bottom, Space.x2)
        .background(alignment: .top) {
            // Fade the scrolling content into the bar instead of cutting it off.
            VStack(spacing: 0) {
                LinearGradient(colors: [Color.surface.opacity(0), Color.surface], startPoint: .top, endPoint: .bottom)
                    .frame(height: 28)
                Color.surface
            }
            .padding(.top, -Space.x4)
            .ignoresSafeArea(edges: .bottom)
        }
    }
}

// MARK: - Record

/// The records this run just set, beside the trophy art.
private struct RecordEarnedCard: View {
    let achievements: [RecordAchievement]
    let unit: UnitSystem

    var body: some View {
        HStack(alignment: achievements.count == 1 ? .center : .top, spacing: 14) {
            ArtThumbnail(name: "recordsTrophy", width: 72, height: 72)
            VStack(alignment: .leading, spacing: 2) {
                Text(achievements.count == 1 ? "Personal record" : "\(achievements.count) personal records")
                    .font(.metricLabel)
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(.track)
                ForEach(Array(achievements.enumerated()), id: \.element.id) { index, achievement in
                    row(achievement)
                        .padding(.top, index > 0 ? Space.x2 : 0)
                }
            }
        }
        .padding(.vertical, Space.x3)
        .padding(.leading, Space.x3)
        .padding(.trailing, Space.x4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .combine)
    }

    private func row(_ achievement: RecordAchievement) -> some View {
        let formatted = achievement.kind.formatted(achievement.value, unit: unit)
        return HStack(alignment: .center, spacing: Space.x2) {
            VStack(alignment: .leading, spacing: 2) {
                Text(RecordBook.title(achievement))
                    .font(.headline)
                    .foregroundStyle(.ink)
                if let improvement = RecordBook.improvement(achievement, unit: unit) {
                    Text(improvement)
                        .font(.footnote)
                        .foregroundStyle(.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                Text(formatted.value)
                    .font(.metricMedium)
                    .monospacedDigit()
                    .foregroundStyle(.ink)
                if let symbol = formatted.unit {
                    Text(symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.inkMuted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }
}

// MARK: - Splits

/// One bar per kilometer (or mile), taller when faster and colored by pace against the run's
/// average; the fastest full split's pace in bold. Scrolls sideways past eight splits.
private struct SplitBars: View {
    let splits: [Split]
    let unit: UnitSystem
    let averagePace: Double?

    private static let tallest: CGFloat = 90

    var body: some View {
        let fastestID = Split.fastest(in: splits, unit: unit)?.id
        let range = paceRange
        Group {
            if splits.count <= 8 {
                HStack(alignment: .bottom, spacing: Space.x1) {
                    ForEach(splits) { split in
                        column(split, isFastest: split.id == fastestID, range: range)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .bottom, spacing: Space.x1) {
                        ForEach(splits) { split in
                            column(split, isFastest: split.id == fastestID, range: range)
                                .frame(width: 40)
                        }
                    }
                }
                .contentMargins(.horizontal, Space.x4, for: .scrollContent)
                .padding(.horizontal, -Space.x4)
            }
        }
        .padding(Space.x4)
        .frame(maxWidth: .infinity)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
    }

    /// Paces of the full splits: the partial last one doesn't set the scale.
    private var paceRange: ClosedRange<Double>? {
        let paces = splits.filter { !$0.isPartial(in: unit) }.compactMap { $0.pace(in: unit) }
        guard let fastest = paces.min(), let slowest = paces.max() else { return nil }
        return fastest...slowest
    }

    private func column(_ split: Split, isFastest: Bool, range: ClosedRange<Double>?) -> some View {
        let pace = split.pace(in: unit)
        let label = split.isPartial(in: unit)
            ? RunFormat.distance(split.distance, unit: unit, fractionDigits: 1)
            : "\(split.index)"
        return VStack(spacing: 6) {
            Text(RunFormat.pace(pace))
                .font(.caption2.weight(isFastest ? .bold : .medium))
                .monospacedDigit()
                .foregroundStyle(isFastest ? Color.ink : Color.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            UnevenRoundedRectangle(topLeadingRadius: 8, bottomLeadingRadius: 3, bottomTrailingRadius: 3,
                                   topTrailingRadius: 8, style: .continuous)
                .fill(PaceScale.color(pace: pace, average: averagePace))
                .frame(width: 26, height: Self.tallest * fraction(pace, range: range))
            Text(label)
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(isFastest ? Color.ink : Color.inkMuted)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(split.isPartial(in: unit) ? "Last \(label) \(unit.distanceSymbol)" : "\(unit == .metric ? "Kilometer" : "Mile") \(split.index)")
        .accessibilityValue("\(RunFormat.pace(pace)) \(unit.paceSymbol)\(isFastest ? ", fastest" : "")")
    }

    /// 1 for the fastest split, 0.4 for the slowest, linear in between.
    private func fraction(_ pace: Double?, range: ClosedRange<Double>?) -> Double {
        guard let pace, let range, range.upperBound > range.lowerBound else { return 0.7 }
        let position = (range.upperBound - pace) / (range.upperBound - range.lowerBound)
        return min(max(0.4 + 0.6 * position, 0.4), 1)
    }
}

// MARK: - Heart rate zones

/// Time in each zone: one bar split by zone, then each zone's number, name and time.
private struct ZoneShareCard: View {
    let seconds: [HeartRateZone: TimeInterval]

    private var total: TimeInterval { seconds.values.reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            GeometryReader { geo in
                let present = HeartRateZone.allCases.filter { (seconds[$0] ?? 0) > 0 }
                let available = max(geo.size.width - 2 * CGFloat(max(present.count - 1, 0)), 0)
                HStack(spacing: 2) {
                    ForEach(present, id: \.self) { zone in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(zone.color)
                            .frame(width: total > 0 ? available * (seconds[zone] ?? 0) / total : 0)
                    }
                }
            }
            .frame(height: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(mostTimeLabel)

            HStack(alignment: .top, spacing: 6) {
                ForEach(HeartRateZone.allCases, id: \.self) { zone in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Circle().fill(zone.color).frame(width: 6, height: 6)
                            Text(verbatim: "Z\(zone.rawValue)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(zone.color)
                        }
                        Text(zone.name)
                            .font(.caption2)
                            .foregroundStyle(.inkMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Text(RunFormat.duration(seconds[zone] ?? 0))
                            .font(.footnote.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Zone \(zone.rawValue), \(zone.name)")
                    .accessibilityValue(RunFormat.duration(seconds[zone] ?? 0))
                }
            }
        }
        .raisedCard()
    }

    private var mostTimeLabel: String {
        guard let top = seconds.max(by: { $0.value < $1.value })?.key else { return "Heart rate zones" }
        return "Most time in zone \(top.rawValue), \(top.name.lowercased())"
    }
}

// MARK: - Shoe

/// Shown after a run that took a shoe close to (or past) its replacement distance.
struct ShoeWearNotice: View {
    let shoe: Shoe
    let unit: UnitSystem

    var body: some View {
        HStack(alignment: .top, spacing: Space.x3) {
            IconBadge("shoe", style: .tinted(shoe.wear >= 1 ? .danger : .warning))
            VStack(alignment: .leading, spacing: Space.x2) {
                Text(shoe.wear >= 1 ? "Time for new shoes" : "\(shoe.displayName) is nearly worn out")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.ink)
                Text("\(shoe.displayName) has \(ShoeWear.distance(shoe.totalDistance, unit: unit)) \(unit.distanceSymbol) on it. You planned to replace it at \(ShoeWear.distance(shoe.maxDistance, unit: unit)) \(unit.distanceSymbol).")
                    .font(.footnote)
                    .foregroundStyle(.inkMuted)
                LinkButton("Retire shoe") { ShoeDefaults.setRetired(shoe, true) }
            }
        }
        .raisedCard()
    }
}

// MARK: - Pickers

/// How the run felt: five faces in a row, one selectable, tap again to clear.
struct FeelingPicker: View {
    @Binding var selection: Feeling?

    var body: some View {
        HStack(spacing: Space.x2) {
            ForEach(Feeling.allCases) { feeling in
                let isSelected = selection == feeling
                Button {
                    selection = isSelected ? nil : feeling
                } label: {
                    VStack(spacing: 6) {
                        FeelingFace(feeling)
                        Text(feeling.title)
                            .font(.footnote.weight(.medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(.ink)
                    .frame(maxWidth: .infinity, minHeight: 72)
                    .background(isSelected ? Color.trackSoft : Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.track, lineWidth: 2)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: Radius.md))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(feeling.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How did it feel")
        .sensoryFeedback(.selection, trigger: selection)
    }
}

/// The surface run on: chips that wrap onto a second line, one selectable, tap again to clear.
struct SurfacePicker: View {
    @Binding var selection: Surface?

    var body: some View {
        ChipFlowLayout(spacing: Space.x2, lineSpacing: Space.x2) {
            ForEach(Surface.allCases) { surface in
                SelectableChip(surface.title, isSelected: selection == surface) {
                    selection = selection == surface ? nil : surface
                }
            }
        }
    }
}

/// Lays chips out in rows, wrapping to a new row when the next one doesn't fit.
private nonisolated struct ChipFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private nonisolated struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(indices: [index], width: size.width, height: size.height)
            } else {
                current.indices.append(index)
                current.width = needed
                current.height = max(current.height, size.height)
            }
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
