import SwiftUI
import SwiftData
import StrideKit
import StrideUI

/// A finished run: the route map across the top (under the bar, with Share and Edit floating over
/// it), the title and date, the distance, the numbers, records it holds, splits, pace, elevation
/// and heart rate along the route, zones, and how it felt. Delete is in the edit sheet.
struct RunDetailView: View {
    @Bindable var run: Run
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.maxHeartRate) private var maxHeartRate = HeartRateZone.defaultMaxHeartRate

    @State private var route: [RoutePoint] = []
    @State private var splits: [Split] = []
    @State private var paceSeries: [SeriesPoint] = []
    @State private var elevationSeries: [SeriesPoint] = []
    @State private var heartRateSeries: [SeriesPoint] = []
    /// Heart rate, kept apart from the run on this device.
    @State private var vitals: RunVitals?
    @State private var zoneSeconds: [HeartRateZone: TimeInterval] = [:]
    /// The highest heart rate recorded, from the raw readings (the chart's line is smoothed).
    @State private var peakHeartRate: Double?
    @State private var sharing = false
    @State private var editing = false
    /// Delete was confirmed in the edit sheet: the run goes once the sheet is down.
    @State private var deleteAfterEditing = false
    /// The title in the bar, once the one on the page has scrolled under it.
    @State private var showsBarTitle = false

    /// Map height, under the status and navigation bars.
    private static let mapHeight: CGFloat = 276

    var body: some View {
        // The run can be deleted elsewhere (another tab) while this screen is still in a stack.
        if run.isDeleted || run.modelContext == nil {
            ContentUnavailableView("Run deleted", systemImage: "trash")
        } else {
            content
        }
    }

    private var content: some View {
        // Known from the stored preview before the full route is decoded, so the layout doesn't jump.
        let showsMap = route.isEmpty ? run.preview.count > 1 : route.count > 1
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if showsMap {
                    RunMapHero(route: route, unit: unit)
                        .frame(height: Self.mapHeight)
                }

                VStack(alignment: .leading, spacing: 0) {
                    header

                    RunDistanceHero(distance: run.distance, unit: unit)
                        .padding(.top, Space.x4)

                    RunHighlights(run: run, splits: splits, unit: unit, averageHeartRate: vitals?.averageHeartRate)
                        .padding(.top, Space.x4)

                    if !splits.isEmpty {
                        RunSplitsCard(splits: splits, unit: unit, averagePace: run.averagePace(in: unit),
                                      heartRate: heartRateSeries)
                            .padding(.top, Space.x4)
                    }

                    if RouteChartsCard.hasContent(pace: paceSeries, elevation: elevationSeries, heartRate: heartRateSeries) {
                        RouteChartsCard(pace: paceSeries, elevation: elevationSeries, heartRate: heartRateSeries, unit: unit,
                                        averagePace: run.averagePace(in: unit), elevationGain: run.elevationGain,
                                        averageHeartRate: vitals?.averageHeartRate, maxHeartRate: maxHeartRate)
                            .padding(.top, Space.x3)
                    }

                    if !zoneSeconds.isEmpty {
                        RunZonesCard(seconds: zoneSeconds, averageHeartRate: vitals?.averageHeartRate,
                                     maxHeartRate: peakHeartRate)
                            .padding(.top, Space.x3)
                    }

                    RunNotesCard(run: run, unit: unit)
                        .padding(.top, Space.x3)
                }
                .padding(.horizontal, Space.x4)
                .padding(.top, Space.x4)
                .padding(.bottom, Space.x5)
            }
        }
        // The map runs up under the bar; without one the page starts below it.
        .ignoresSafeArea(.container, edges: showsMap ? .top : [])
        .scrollDismissesKeyboard(.interactively)
        .background(Color.surface)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > (showsMap ? Self.mapHeight - 46 : 50)
        } action: { _, isUnder in
            showsBarTitle = isUnder
        }
        .navigationTitle(run.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // A title view, never a glass button.
            if #available(iOS 26, *) {
                ToolbarItem(placement: .principal) { barTitle }
                    .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .principal) { barTitle }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Share run", systemImage: "square.and.arrow.up") { sharing = true }
            }
            // Share and Edit as two separate glass shapes, as designed.
            if #available(iOS 26, *) {
                ToolbarSpacer(.fixed, placement: .topBarTrailing)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing, onDismiss: {
            guard deleteAfterEditing else { return }
            deleteAfterEditing = false
            deleteRun()
        }) {
            EditRunView(run: run) { deleteAfterEditing = true }
        }
        .sheet(isPresented: $sharing) {
            ShareRunSheet(share: ShareRun(run: run, unit: unit))
        }
        .task(id: unit) { await load() }
    }

    /// The run's name in the bar, faded in once the page's own title has scrolled under it.
    private var barTitle: some View {
        Text(run.title)
            .font(.headline)
            .foregroundStyle(.ink)
            .lineLimit(1)
            .opacity(showsBarTitle ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: showsBarTitle)
            .accessibilityHidden(!showsBarTitle)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(run.title)
                .font(.largeTitle.bold())
                .foregroundStyle(.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    dateText
                    sourceChip
                }
                VStack(alignment: .leading, spacing: 6) {
                    dateText
                    sourceChip
                }
            }
        }
    }

    /// "Thu 24 Sep 2026 · 06:40".
    private var dateText: some View {
        Text("\(run.startDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())) · \(run.startDate.formatted(date: .omitted, time: .shortened))")
            .font(.subheadline)
            .foregroundStyle(.inkMuted)
            .lineLimit(1)
    }

    /// Where the run came from: Apple Watch, or typed in by hand. iPhone runs need no label.
    @ViewBuilder private var sourceChip: some View {
        if run.isManual {
            SourceChip(title: "Manual", systemImage: "square.and.pencil", spoken: "Added by hand")
        } else if run.source == .watch {
            SourceChip(title: "Apple Watch", systemImage: "applewatch", spoken: "Recorded on Apple Watch")
        }
    }

    // MARK: Loading and deleting

    /// Decoding and analysis run off the main actor, so opening a long run doesn't stall the push.
    private func load() async {
        if vitals == nil {
            vitals = Vitals.of(run.id, in: context)
            zoneSeconds = vitals?.zoneSeconds ?? [:]
            peakHeartRate = vitals?.heartRates.compactMap { $0 }.max()
        }
        let data = await RouteAnalysis.chartData(
            routeData: route.isEmpty ? run.routeData : nil, decodedRoute: route, heartRates: vitals?.heartRates ?? [],
            distance: run.distance, duration: run.duration, source: run.source, unit: unit
        )
        guard !Task.isCancelled else { return }
        route = data.route
        splits = data.imperialSplits ?? run.splits
        paceSeries = data.pace
        elevationSeries = data.elevation
        heartRateSeries = data.heartRate
    }

    private func deleteRun() {
        let run = self.run
        dismiss()
        // Delete after the pop so this screen never renders a deleted model.
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            HealthSync.shared.delete(workoutID: run.healthWorkoutID)
            Vitals.delete(run, in: context)
            try? context.save()
        }
    }
}

// MARK: - Map

/// The route across the top of the page, with a scrim under the bar's buttons and the pace key.
/// Its own view, so the route's colors are worked out again only when the route changes.
private struct RunMapHero: View {
    let route: [RoutePoint]
    let unit: UnitSystem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if route.count > 1 {
                RouteMapView(points: route, splitMarkers: unit)
                    // Frames the route and lifts the map's logo and Legal link above the pace key.
                    .safeAreaPadding(.bottom, 44)
                    .accessibilityLabel("Route map, colored by pace")
            } else {
                // While the route decodes.
                Color.surfaceSunken
            }
            // Keeps the bar's buttons readable over the map.
            LinearGradient(colors: [Color.surface.opacity(0.75), Color.surface.opacity(0)], startPoint: .top, endPoint: .bottom)
                .frame(height: 110)
                .frame(maxHeight: .infinity, alignment: .top)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            if route.count > 1 {
                PaceScaleLegend()
                    .padding(.leading, Space.x4)
                    .padding(.bottom, 10)
            }
        }
        .clipped()
    }
}

/// A small outlined capsule after the date: "Apple Watch".
private struct SourceChip: View {
    let title: String
    let systemImage: String
    let spoken: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
            Text(title)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.ink)
        .lineLimit(1)
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Color.surfaceRaised, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.line, lineWidth: 1))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }
}

// MARK: - Metrics and records

/// The metrics grid, with a trophy on metrics that hold a record, and a card for the records this
/// run set and still holds, leading to all of them.
private struct RunHighlights: View {
    let run: Run
    let splits: [Split]
    let unit: UnitSystem
    let averageHeartRate: Double?
    @Query private var runs: [Run]

    var body: some View {
        let records = Self.records(of: run, among: runs)
        VStack(alignment: .leading, spacing: Space.x3) {
            RunMetricsGrid(run: run, splits: splits, unit: unit, averageHeartRate: averageHeartRate,
                           records: Set(records.map(\.achievement.kind)))
            if !records.isEmpty {
                NavigationLink(value: ProgressRoute.records) {
                    RecordCard(records: records, unit: unit)
                }
                .buttonStyle(.plain)
            }
        }
    }

    struct HeldRecord: Identifiable {
        let achievement: RecordAchievement
        /// When the record it beat was set.
        let previousDate: Date?
        var id: String { achievement.id }
    }

    /// Records this run set and still holds, with what they beat, the most notable first. A first
    /// time counts for 5K and longer, as on the run summary.
    static func records(of run: Run, among runs: [Run]) -> [HeldRecord] {
        let entries = runs.map(\.recordEntry)
        let held = Set(PersonalRecords.best(of: entries).values.filter { $0.runID == run.id }.map(\.kind))
        guard !held.isEmpty else { return [] }
        let earlier = PersonalRecords.best(of: entries.filter { $0.id != run.id && $0.date < run.startDate })
        return PersonalRecords.achievements(of: run.recordEntry, previous: entries)
            .filter { held.contains($0.kind) }
            .sorted { priority($0.kind) > priority($1.kind) }
            .map { HeldRecord(achievement: $0, previousDate: earlier[$0.kind]?.date) }
    }

    private static func priority(_ kind: RecordKind) -> Double {
        switch kind {
        case .effort(let distance): distance.meters
        case .longestDistance: 500
        case .longestDuration: 400
        case .mostElevation: 300
        }
    }
}

/// "NEW RECORD / Most climbing · 142 m / Previous best 118 m, Sun 20 Sep", with the trophy art.
private struct RecordCard: View {
    let records: [RunHighlights.HeldRecord]
    let unit: UnitSystem

    var body: some View {
        HStack(spacing: 14) {
            ArtThumbnail(name: "recordsTrophy", width: 56, height: 56)
            VStack(alignment: .leading, spacing: 2) {
                Text(records.count == 1 ? "New record" : "\(records.count) new records")
                    .font(.metricLabel)
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(.track)
                if let first = records.first {
                    Text("\(first.achievement.kind.title) · \(value(first.achievement))")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.ink)
                    Text(detail(first))
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.inkMuted)
                }
                if records.count > 1 {
                    Text("Also \(others)")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.inkMuted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            DisclosureChevron()
        }
        .raisedCard(padding: Space.x3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows all your records")
    }

    private func value(_ achievement: RecordAchievement) -> String {
        let formatted = achievement.kind.formatted(achievement.value, unit: unit)
        return [formatted.value, formatted.unit].compactMap { $0 }.joined(separator: " ")
    }

    /// "Previous best 118 m, Sun 20 Sep", or "Your first 10K".
    private func detail(_ record: RunHighlights.HeldRecord) -> String {
        guard let previous = record.achievement.previous else {
            if case .effort(let distance) = record.achievement.kind { return "Your first \(distance.title)" }
            return "Your first run"
        }
        let formatted = record.achievement.kind.formatted(previous, unit: unit)
        let value = [formatted.value, formatted.unit].compactMap { $0 }.joined(separator: " ")
        guard let date = record.previousDate else { return "Previous best \(value)" }
        let thisYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
        let day = date.formatted(thisYear ? .dateTime.weekday(.abbreviated).day().month(.abbreviated)
                                          : .dateTime.day().month(.abbreviated).year())
        return "Previous best \(value), \(day)"
    }

    /// "fastest 1K and longest run".
    private var others: String {
        let titles = records.dropFirst().map { record in
            let title = record.achievement.kind.title
            return title.prefix(1).lowercased() + title.dropFirst()
        }
        return titles.formatted(.list(type: .and))
    }
}

// MARK: - Notes

/// How it felt, the surface, the shoe and notes, in one card. Changes save with the run.
private struct RunNotesCard: View {
    @Bindable var run: Run
    let unit: UnitSystem

    var body: some View {
        GroupedCard {
            feelingRow
            surfaceRow
            if let shoe = run.shoe {
                NavigationLink(value: shoe) {
                    ShoeWearRow(shoe: shoe, unit: unit, iconSize: 36, titleFont: .body.weight(.semibold),
                                barHeight: 4, showsChevron: true)
                        .padding(.horizontal, Space.x4)
                        .padding(.vertical, 10)
                        .frame(minHeight: 60)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            notesRow
        }
    }

    private var feelingRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.x2) {
                feelingTitle
                Spacer(minLength: 0)
                faces
            }
            VStack(alignment: .leading, spacing: Space.x1) {
                feelingTitle
                faces
            }
            .padding(.vertical, Space.x2)
        }
        .padding(.leading, Space.x4)
        .padding(.trailing, Space.x3)
        .padding(.vertical, Space.x1)
        .frame(minHeight: 52)
    }

    private var feelingTitle: some View {
        Group {
            if let feeling = run.feeling {
                Text("Felt \(Text(feeling.title).fontWeight(.semibold))")
            } else {
                Text("How did it feel?")
            }
        }
        .font(.body)
        .foregroundStyle(.ink)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private var faces: some View {
        HStack(spacing: 2) {
            ForEach(Feeling.allCases) { feeling in
                let isSelected = run.feeling == feeling
                Button {
                    run.feeling = isSelected ? nil : feeling
                } label: {
                    FeelingFace(feeling, size: 24)
                        .foregroundStyle(isSelected ? Color.track : Color.inkMuted)
                        .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: 12).fill(Color.trackSoft)
                                RoundedRectangle(cornerRadius: 12).strokeBorder(Color.track, lineWidth: 1.5)
                            }
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(feeling.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: run.feeling)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("How it felt")
    }

    private var surfaceRow: some View {
        HStack(spacing: Space.x2) {
            Text("Surface")
                .font(.body)
                .foregroundStyle(.ink)
            Spacer(minLength: Space.x2)
            Picker("Surface", selection: $run.surface) {
                Text("None").tag(Surface?.none)
                ForEach(Surface.allCases) { Text($0.title).tag(Surface?.some($0)) }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .tint(.lane)
        }
        .padding(.leading, Space.x4)
        .padding(.trailing, Space.x2)
        .frame(minHeight: 52)
    }

    private var notesRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Notes")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
                .accessibilityHidden(true)
            TextField("How did it go?", text: $run.notes, axis: .vertical)
                .font(.subheadline)
                .foregroundStyle(.ink)
                .lineLimit(1...6)
                .accessibilityLabel("Notes")
        }
        .padding(.horizontal, Space.x4)
        .padding(.top, 10)
        .padding(.bottom, Space.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
