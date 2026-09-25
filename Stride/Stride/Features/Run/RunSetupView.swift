import SwiftUI
import SwiftData
import MapKit
import StrideKit
import StrideUI

/// Pick a run type and target, check GPS, and start.
struct RunSetupView: View {
    @Environment(RunTracker.self) private var tracker
    @Environment(\.openURL) private var openURL
    @Query(filter: #Predicate<Shoe> { !$0.isRetired }, sort: \Shoe.createdAt) private var shoes: [Shoe]
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.autoPause) private var autoPause = true

    @State private var runType: RunType = .free
    @State private var targetMeters: Double = 5_000
    @State private var targetMinutes = 30
    @State private var shoeID: UUID?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)

    /// Intervals arrive with the coach in phase 4.
    private let runTypes: [RunType] = [.free, .distance, .time]
    private let timeOptions = [15, 20, 30, 45, 60, 90]

    private struct DistancePreset: Hashable {
        let label: String
        let meters: Double
    }

    /// Race distances are exact in both unit systems; everyday distances follow the runner's unit.
    private var distancePresets: [DistancePreset] {
        let half = DistancePreset(label: "Half", meters: 21_097.5)
        let marathon = DistancePreset(label: "Marathon", meters: 42_195)
        switch unit {
        case .metric:
            return [1, 3, 5, 10].map { DistancePreset(label: "\($0) km", meters: Double($0) * 1_000) } + [half, marathon]
        case .imperial:
            let miles = { (n: Int) in DistancePreset(label: "\(n) mi", meters: Double(n) * 1_609.344) }
            return [miles(1), miles(2), DistancePreset(label: "5K", meters: 5_000), miles(5),
                    DistancePreset(label: "10K", meters: 10_000), half, marathon]
        }
    }

    /// The chosen target if it's one of the current unit's presets, otherwise 5K, so the highlighted
    /// chip and the run's target always agree after a unit change.
    private var selectedMeters: Double {
        distancePresets.contains { $0.meters == targetMeters } ? targetMeters : 5_000
    }

    private var canStart: Bool { !tracker.authorizationDenied && !tracker.accuracyLimited }

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
        }
        // An inset, not an overlay, so the map centers the runner in the area above the panel.
        .safeAreaInset(edge: .bottom) {
            panel
                .padding(.horizontal, Space.x4)
                .padding(.bottom, Space.x2)
        }
        .onAppear { tracker.startPreview() }
        .onDisappear { tracker.stopPreview() }
    }

    private var panel: some View {
        VStack(spacing: Space.x4) {
            HStack {
                GPSChip(quality: tracker.gpsQuality)
                Spacer()
            }

            if tracker.authorizationDenied {
                locationBanner(title: "Location is off for Stride",
                               message: "Turn on location access to record your route, distance and pace.")
            } else if tracker.accuracyLimited {
                locationBanner(title: "Precise Location is off",
                               message: "Stride needs Precise Location to measure distance and pace. Turn it on in Settings.")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x2) {
                    ForEach(runTypes) { type in
                        SelectableChip(type.title, isSelected: runType == type) { runType = type }
                    }
                }
            }

            targetPicker
                .frame(minHeight: 36)

            settings

            RunControlButton(.start) { tracker.start(configuration) }
                .disabled(!canStart)
                .opacity(canStart ? 1 : 0.4)
        }
        .padding(Space.x4)
        .glassPanel()
    }

    @ViewBuilder private var targetPicker: some View {
        switch runType {
        case .distance:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x2) {
                    ForEach(distancePresets, id: \.self) { preset in
                        SelectableChip(preset.label, isSelected: selectedMeters == preset.meters) {
                            targetMeters = preset.meters
                        }
                    }
                }
            }
        case .time:
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Space.x2) {
                    ForEach(timeOptions, id: \.self) { minutes in
                        SelectableChip("\(minutes) min", isSelected: targetMinutes == minutes) {
                            targetMinutes = minutes
                        }
                    }
                }
            }
        case .free, .intervals:
            Text("Run at your own pace. Stride records everything.")
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shoe and auto-pause as settings rows, grouped like a small form.
    private var settings: some View {
        VStack(spacing: 0) {
            if !shoes.isEmpty {
                Menu {
                    Picker("Shoe", selection: $shoeID) {
                        Text("No shoe").tag(UUID?.none)
                        ForEach(shoes) { shoe in
                            Text(shoe.name).tag(UUID?.some(shoe.id))
                        }
                    }
                } label: {
                    HStack(spacing: Space.x2) {
                        Label("Shoe", systemImage: "shoe.fill")
                            .foregroundStyle(.ink)
                        Spacer()
                        Text(shoes.first { $0.id == shoeID }?.name ?? "None")
                            .foregroundStyle(.inkMuted)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.caption)
                            .foregroundStyle(.inkMuted)
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, Space.x4)
                    .frame(minHeight: Dimension.hitMin)
                    .contentShape(Rectangle())
                }
                Divider()
                    .overlay(Color.line)
                    .padding(.leading, Space.x4)
            }
            Toggle(isOn: $autoPause) {
                Label("Auto-pause", systemImage: "pause.circle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.ink)
            }
            .tint(.track)
            .padding(.horizontal, Space.x4)
            .frame(minHeight: Dimension.hitMin)
        }
        .background(Color.surfaceSunken.opacity(0.85), in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
    }

    private func locationBanner(title: String, message: String) -> some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.ink)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.inkMuted)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.lane)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.x4)
        .background(Color.trackSoft, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private var configuration: RunTracker.Configuration {
        var configuration = RunTracker.Configuration(type: runType, shoeID: shoeID, autoPause: autoPause)
        switch runType {
        case .distance: configuration.targetDistance = selectedMeters
        case .time: configuration.targetDuration = TimeInterval(targetMinutes * 60)
        case .free, .intervals: break
        }
        return configuration
    }
}
