import SwiftUI
import SwiftData
import StrideKit
import StrideUI

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
    /// Meters along the route under the finger, shared by all charts.
    @State private var chartSelection: Double?
    @State private var shareImage: Image?
    /// Heart rate, kept apart from the run on this device.
    @State private var vitals: RunVitals?
    @State private var editing = false
    @State private var confirmingDelete = false

    var body: some View {
        // The run can be deleted elsewhere (another tab) while this screen is still in a stack.
        if run.isDeleted || run.modelContext == nil {
            ContentUnavailableView("Run deleted", systemImage: "trash")
        } else {
            content
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text(run.startDate.formatted(date: .complete, time: .shortened))
                        .font(.subheadline)
                        .foregroundStyle(.inkMuted)
                    RecordBadges(runID: run.id)
                }

                RunReport(run: run, route: route, splits: splits, unit: unit, vitals: vitals)

                charts

                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("How did it feel?").font(.headline).foregroundStyle(.ink)
                    FeelingPicker(selection: $run.feeling)
                }

                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("Surface").font(.headline).foregroundStyle(.ink)
                    SurfacePicker(selection: $run.surface)
                }

                VStack(alignment: .leading, spacing: Space.x3) {
                    Text("Notes").font(.headline).foregroundStyle(.ink)
                    TextField("How did it go?", text: $run.notes, axis: .vertical)
                        .lineLimit(3...6)
                        .padding(Space.x4)
                        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                }

                if let shoe = run.shoe {
                    NavigationLink(value: shoe) {
                        HStack(spacing: Space.x3) {
                            ShoeIcon(shoe: shoe, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Shoe").metricLabelStyle()
                                Text(shoe.displayName).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                            }
                            Spacer()
                            Text("\(ShoeWear.distance(shoe.totalDistance, unit: unit)) \(unit.distanceSymbol)")
                                .font(.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(.inkMuted)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.inkMuted)
                                .accessibilityHidden(true)
                        }
                        .raisedCard()
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(Space.x4)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color.surface)
        .navigationTitle(run.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let shareImage {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: shareImage, preview: SharePreview(run.title, image: shareImage)) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit", systemImage: "pencil") { editing = true }
                    Button("Delete Run", systemImage: "trash", role: .destructive) { confirmingDelete = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $editing, onDismiss: renderShareImage) {
            EditRunView(run: run)
        }
        .confirmationDialog("Delete this run?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Run", role: .destructive) {
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
        .task(id: unit) { await load() }
        .onChange(of: shareInputs) { renderShareImage() }
    }

    /// Everything the share card shows, so the image is redrawn whenever any of it changes.
    private struct ShareInputs: Equatable {
        let title: String
        let date: Date
        let distance: Double
        let duration: TimeInterval
        let elevationGain: Double
    }

    private var shareInputs: ShareInputs {
        ShareInputs(title: run.title, date: run.startDate, distance: run.distance, duration: run.duration, elevationGain: run.elevationGain)
    }

    /// One distance axis for all charts, so a selection lines up across them.
    private var xDomain: ClosedRange<Double> {
        let end = [paceSeries.last, elevationSeries.last, heartRateSeries.last].compactMap { $0?.distance }.max() ?? 0
        return 0...Swift.max(end / unit.metersPerUnit, 0.1)
    }

    @ViewBuilder private var charts: some View {
        if paceSeries.count > 2 {
            let selected = paceSeries.nearest(to: chartSelection)
            ChartCard(title: "Pace", summary: selected.map { "\(atDistance($0)) · \(RunFormat.pace($0.value)) \(unit.paceSymbol)" }
                      ?? "Avg \(RunFormat.pace(run.averagePace(in: unit))) \(unit.paceSymbol)") {
                PaceChart(series: paceSeries, unit: unit, average: run.averagePace(in: unit), xDomain: xDomain, selection: $chartSelection)
            }
        }
        if elevationSeries.count > 2 {
            let selected = elevationSeries.nearest(to: chartSelection)
            ChartCard(title: "Elevation", summary: selected.map { "\(atDistance($0)) · \(Int(unit.elevation(fromMeters: $0.value))) \(unit.elevationSymbol)" }
                      ?? "+\(Int(unit.elevation(fromMeters: run.elevationGain))) \(unit.elevationSymbol)") {
                ElevationChart(series: elevationSeries, unit: unit, xDomain: xDomain, selection: $chartSelection)
            }
        }
        if heartRateSeries.count > 2 {
            let selected = heartRateSeries.nearest(to: chartSelection)
            ChartCard(title: "Heart rate", summary: selected.map { "\(atDistance($0)) · \(Int($0.value)) bpm" }
                      ?? vitals?.averageHeartRate.map { "Avg \(Int($0)) bpm" } ?? "") {
                HeartRateChart(series: heartRateSeries, unit: unit, maxHeartRate: maxHeartRate, xDomain: xDomain, selection: $chartSelection)
            }
        }
    }

    private func atDistance(_ point: SeriesPoint) -> String {
        "\(RunFormat.distance(point.distance, unit: unit, fractionDigits: 1)) \(unit.distanceSymbol)"
    }

    /// Decoding and analysis run off the main actor, so opening a long run doesn't stall the push.
    private func load() async {
        if vitals == nil { vitals = Vitals.of(run.id, in: context) }
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
        renderShareImage()
    }

    private func renderShareImage() {
        shareImage = ShareCardView(title: run.title, date: run.startDate, distance: run.distance, duration: run.duration,
                                   elevationGain: run.elevationGain, coordinates: run.preview, unit: unit).image()
    }
}
