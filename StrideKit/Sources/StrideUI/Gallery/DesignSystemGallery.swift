import SwiftUI
import StrideKit

/// Every token and component on one scrolling screen, for checking the design system on device.
public struct DesignSystemGallery: View {
    @State private var selectedType = "Distance"
    @State private var finished = 0

    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x5) {
                section("Colors") {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72), spacing: Space.x3)], spacing: Space.x3) {
                        ForEach(Self.swatches, id: \.0) { name, color in
                            VStack(spacing: Space.x1) {
                                RoundedRectangle(cornerRadius: Radius.sm)
                                    .fill(color)
                                    .frame(height: 44)
                                    .overlay(RoundedRectangle(cornerRadius: Radius.sm).strokeBorder(Color.line))
                                Text(name).font(.caption2).foregroundStyle(.inkMuted)
                            }
                        }
                    }
                }

                section("Metrics") {
                    MetricView("Distance", value: "12.46", unit: "km", size: .hero)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Space.x3), GridItem(.flexible())], spacing: Space.x3) {
                        MetricTile("Time", value: "48:31")
                        MetricTile("Avg pace", value: "5'12\"", unit: "/km")
                        MetricTile("Calories", value: "612", unit: "kcal")
                        MetricTile("Elevation", value: "84", unit: "m")
                    }
                }

                #if os(iOS)
                section("Run controls") {
                    HStack(spacing: Space.x4) {
                        RunControlButton(.start) {}
                        RunControlButton(.pause) {}
                        HoldToConfirmButton { finished += 1 }
                    }
                    Text(finished == 0 ? "Hold the red button to finish" : "Finished \(finished)×")
                        .font(.caption).foregroundStyle(.inkMuted)
                }
                #endif

                section("Buttons") {
                    Button("Start workout") {}.buttonStyle(.stridePrimary)
                    Button("Add manual run") {}.buttonStyle(.strideSecondary)
                }

                section("Chips") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.x2) {
                            ForEach(["Free run", "Distance", "Time", "Intervals"], id: \.self) { type in
                                SelectableChip(type, isSelected: selectedType == type) { selectedType = type }
                            }
                        }
                    }
                    HStack(spacing: Space.x2) {
                        StatusChip("GPS strong", indicator: .success)
                        StatusChip("GPS weak", indicator: .warning)
                        StatusChip("Auto-paused", background: .trackSoft)
                    }
                }

                section("Progress ring") {
                    HStack(spacing: Space.x5) {
                        ProgressRing(progress: 0.71) {
                            VStack(spacing: 2) {
                                Text("14.2").font(.metricSmall).monospacedDigit()
                                Text("of 20 km").metricLabelStyle()
                            }
                        }
                        .frame(width: 132, height: 132)
                        ProgressRing(progress: 1.05) {
                            Image(systemName: "checkmark").font(.title2.bold()).foregroundStyle(.success)
                        }
                        .frame(width: 80, height: 80)
                    }
                }

                section("Splits") {
                    SplitTable(splits: Self.sampleSplits, unit: .metric)
                }

                section("Heart-rate zones") {
                    ZoneBars(seconds: [.maximum: 130, .threshold: 585, .aerobic: 1_442, .easy: 631, .recovery: 123])
                }
            }
            .padding(Space.x4)
        }
        .background(Color.surface)
        .navigationTitle("Design System")
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.x3) {
            Text(title).font(.headline).foregroundStyle(.ink)
            content()
        }
    }

    static let sampleSplits = [
        Split(index: 1, distance: 1_000, duration: 324, elevationDelta: 4),
        Split(index: 2, distance: 1_000, duration: 311, elevationDelta: 12),
        Split(index: 3, distance: 1_000, duration: 298, elevationDelta: -6),
        Split(index: 4, distance: 1_000, duration: 307, elevationDelta: -2),
        Split(index: 5, distance: 1_000, duration: 333, elevationDelta: 9),
        Split(index: 6, distance: 460, duration: 150, elevationDelta: 1),
    ]

    static let swatches: [(String, Color)] = [
        ("surface", .surface), ("raised", .surfaceRaised), ("sunken", .surfaceSunken),
        ("ink", .ink), ("ink muted", .inkMuted), ("line strong", .lineStrong),
        ("track", .track), ("track soft", .trackSoft), ("lane", .lane), ("lane soft", .laneSoft),
        ("success", .success), ("warning", .warning), ("danger", .danger),
        ("zone 1", HeartRateZone.recovery.color), ("zone 2", HeartRateZone.easy.color),
        ("zone 3", HeartRateZone.aerobic.color), ("zone 4", HeartRateZone.threshold.color),
        ("zone 5", HeartRateZone.maximum.color),
    ]
}

#Preview("Light") {
    NavigationStack { DesignSystemGallery() }
}

#Preview("Dark") {
    NavigationStack { DesignSystemGallery() }.preferredColorScheme(.dark)
}
