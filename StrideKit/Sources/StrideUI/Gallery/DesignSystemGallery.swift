import SwiftUI
import StrideKit

/// Every token and component on one scrolling screen, for checking the design system on device.
public struct DesignSystemGallery: View {
    @State private var selectedType = "Distance"
    @State private var finished = 0
    @State private var period = "Month"
    @State private var units = "Kilometers"
    @State private var coachOn = true
    @State private var feeling: Feeling = .good

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
                    ZoneBars(seconds: Self.sampleZones)
                }

                layoutSections
                dataSections
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

    // MARK: Redesign components

    /// Headings, tiles, cards and controls.
    private var layoutSections: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            headingSection
            statSection
            cardSection
            controlSection
            badgeSection
            glowSection
        }
    }

    private var glowSection: some View {
        section("Brand glow") {
            HStack(spacing: Space.x2) {
                ForEach([BrandGlow.Style.blobs, .corner, .spotlight, .wash], id: \.self) { style in
                    Color.surface
                        .overlay { BrandGlow(style) }
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Radius.md).strokeBorder(Color.line))
                }
            }
        }
    }

    /// Weeks, meters, workouts, zones and feelings.
    private var dataSections: some View {
        VStack(alignment: .leading, spacing: Space.x5) {
            weekSection
            trackSection
            stepSection
            zoneSection
            feelingSection
        }
    }

    private var headingSection: some View {
        section("Section headings") {
            SectionHeading("Your plan") {
                LinkButton("All sessions") {}
            }
            SectionHeading("Friends", detail: "this week") {
                LinkButton("See all") {}
            }
            SectionHeading("Splits", caption: "Avg 5'45\" /km")
            SectionHeading("Voice coach", style: .overline) {
                LinkButton("Test voice", systemImage: "play.fill") {}
            }
            LinkButton("All weeks and sessions", showsChevron: true) {}
        }
    }

    private var statSection: some View {
        section("Stat tiles") {
            HStack(spacing: Space.x3) {
                StatTile("September", value: "105.7", unit: "km").raisedCard(padding: Space.x3)
                StatTile("Runs", value: "12").raisedCard(padding: Space.x3)
                StatTile("Streak", value: "5", unit: "weeks").raisedCard(padding: Space.x3)
            }
            DividedGrid(columns: 2) {
                StatTile("Avg pace", value: "5'16\"", unit: "/km", size: .medium)
                StatTile("Avg heart rate", value: "158", unit: "bpm", size: .medium)
                StatTile("Calories", value: "548", unit: "kcal", size: .medium)
                StatTile("Elevation", value: "24", unit: "m", size: .medium, symbol: .record)
            }
            HStack(spacing: Space.x2) {
                StatTile("5K", value: "24:12", symbol: .leading("trophy"), footnote: "Sep 22")
                    .raisedCard(padding: Space.x3, fill: .surfaceSunken)
                StatTile("Half marathon", value: "1:51:20", size: .medium, footnote: "5'17\" /km")
                    .raisedCard(padding: Space.x3, fill: .surfaceSunken)
            }
            DividedGrid(columns: 2, dividers: .rows, alignment: .center,
                        cellPadding: EdgeInsets(top: Space.x4, leading: 0, bottom: Space.x4, trailing: 0), fill: nil) {
                StatTile("Time", value: "22:52", size: .large, alignment: .center)
                StatTile("Pace", value: "4'43\"", unit: "/km", size: .large, alignment: .center)
                StatTile("Avg pace", value: "5'45\"", unit: "/km", size: .large, alignment: .center)
                StatTile("Heart rate", value: "171", unit: "bpm", size: .large, alignment: .center) {
                    ZoneChip(.threshold)
                }
            }
        }
    }

    private var cardSection: some View {
        section("Grouped card") {
            GroupedCard(dividerInset: 64) {
                CardRow("Voice coach", subtitle: "Splits, steps and alerts over music", titleWeight: .regular) {
                    IconBadge("speaker.wave.2", style: .sunken, size: 36, corner: .rounded)
                } trailing: {
                    Toggle("Voice coach", isOn: $coachOn).labelsHidden().tint(Color.track)
                }
                CardRow("Units", titleWeight: .regular) {
                    IconBadge("ruler", style: .sunken, size: 36, corner: .rounded)
                } trailing: {
                    PillPicker("Units", selection: $units, options: ["Kilometers", "Miles"], size: .compact,
                               background: .surfaceSunken) { $0 }
                }
                CardRow("Winter Trainer", subtitle: "Retired after 731 km") {
                    IconBadge("shoe", style: .tinted(.inkMuted))
                } trailing: {
                    DisclosureChevron()
                }
            }
        }
    }

    private var controlSection: some View {
        section("Controls") {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(colors: [HeartRateZone.easy.color, HeartRateZone.maximum.color],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                HStack(spacing: Space.x2) {
                    GlassIconButton("location.fill", accessibilityLabel: "Center on your location", tint: .lane) {}
                    GlassIconButton("square.and.arrow.up", accessibilityLabel: "Share run") {}
                    Spacer()
                    GlassCapsuleButton("Edit") {}
                }
                .padding(Space.x3)
                .frame(maxHeight: .infinity, alignment: .top)
                PaceScaleLegend()
                    .padding(Space.x3)
            }
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: Radius.md))
            HStack(spacing: Space.x3) {
                RoundIconButton("map", accessibilityLabel: "Show map") {}
                RoundIconButton("minus", accessibilityLabel: "Lower the goal", style: .outlined, diameter: 48) {}
                RoundIconButton("plus", accessibilityLabel: "Raise weekly goal", style: .sunken, diameter: 32) {}
                RoundIconButton("xmark", accessibilityLabel: "End run", style: .tinted(.danger), diameter: 58, title: "End") {}
                RoundIconButton("pause.fill", accessibilityLabel: "Pause", style: .filled(.track), diameter: 58, title: "Pause") {}
            }
            PillPicker("Period", selection: $period, options: ["Week", "Month", "Year", "All"]) { $0 }
            PillPicker("Units", selection: $units, options: ["Kilometers", "Miles"], size: .large) { $0 }
        }
    }

    private var badgeSection: some View {
        section("Badges and icons") {
            HStack(spacing: Space.x2) {
                SoftBadge("Default", tone: .lane)
                SoftBadge("Next", tone: .brand, uppercase: true)
                SoftBadge("Active", dot: .success)
                SoftBadge("Manual", tone: .muted)
                TagBadge("Pro")
            }
            HStack(spacing: Space.x3) {
                IconBadge("location.fill")
                IconBadge("person.2", style: .lane)
                IconBadge("checkmark", style: .tinted(.success))
                IconBadge("shoe", style: .muted)
                IconBadge("figure.run", style: .raised, size: 32)
                IconBadge("bolt.fill", size: 36, corner: .rounded)
            }
        }
    }

    private var weekSection: some View {
        section("Weeks") {
            WeekBars(days: Self.sampleWeek)
                .frame(maxWidth: 200)
            let suggestion = WeekPlanSuggestion(weeklyGoal: 30, unit: .metric)
            WeekPlanStrip(weekdays: suggestion.weekdays)
            Text(suggestion.sentence(unit: .metric))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
        }
    }

    private var trackSection: some View {
        section("Track bars") {
            TrackBar(progress: 0.38)
            SegmentedProgressBar(count: 8, progress: 2.34)
            TrackBar(progress: 0.724, height: 10, marker: 0.667, markerLabel: "Even pace")
            TrackBar(progress: 0.722, height: 12, marker: 0.625, band: 0.5...0.8125, bandColor: .success,
                     bandPlacement: .below)
            TrackBar(progress: 0.59, tint: HeartRateZone.aerobic.color, band: 0.9...1)
            HStack(spacing: Space.x1) {
                ForEach([1.1, 1.0, 0.95, 0.85], id: \.self) { ratio in
                    RoundedRectangle(cornerRadius: Radius.sm)
                        .fill(PaceScale.color(forSpeedRatio: ratio))
                        .frame(height: 24)
                }
            }
        }
    }

    private var stepSection: some View {
        section("Workout steps") {
            let steps = IntervalPresets.all[0].steps
            StepStrip(steps: steps)
            StepStrip(steps: steps, style: .shaped, height: 28,
                      accessibilityLabel: StepStrip.summary(of: steps, unit: .metric))
            StepStrip(steps: steps, height: 4, currentStep: 5, currentProgress: 0.6)
            StepLegend()
        }
    }

    private var zoneSection: some View {
        section("Zones") {
            HStack(spacing: Space.x2) {
                ZoneChip(.threshold)
                ZoneChip(.aerobic, style: .solid, showsName: false)
                ZoneSwatch(.maximum)
            }
            ZoneScale(height: 20, showsNumbers: true)
            ZoneScale(highlighted: .aerobic, marker: 0.48)
            ZoneTimeList(seconds: Self.sampleZones)
                .raisedCard()
            ZoneTimeList(seconds: Self.sampleZones, style: .compact, current: .aerobic)
        }
    }

    private var feelingSection: some View {
        section("Feelings") {
            HStack(spacing: Space.x2) {
                ForEach(Feeling.allCases) { option in
                    Button {
                        feeling = option
                    } label: {
                        FeelingFace(option)
                            .foregroundStyle(option == feeling ? Color.track : Color.inkMuted)
                            .frame(width: Dimension.hitMin, height: Dimension.hitMin)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(option.title)
                    .accessibilityAddTraits(option == feeling ? .isSelected : [])
                }
            }
        }
    }

    static let sampleZones: [HeartRateZone: TimeInterval] = [
        .maximum: 130, .threshold: 585, .aerobic: 1_442, .easy: 631, .recovery: 123,
    ]

    static let sampleWeek: [WeekBars.Day] = [
        WeekBars.Day(id: 0, letter: "M", value: 11.2, accessibilityLabel: "Monday, 11.2 km"),
        WeekBars.Day(id: 1, letter: "T", value: 8.4, accessibilityLabel: "Tuesday, 8.4 km"),
        WeekBars.Day(id: 2, letter: "W", value: 0, accessibilityLabel: "Wednesday, no run"),
        WeekBars.Day(id: 3, letter: "T", value: 5, accessibilityLabel: "Thursday, 5.0 km"),
        WeekBars.Day(id: 4, letter: "F", value: 0, isToday: true, accessibilityLabel: "Friday, no run"),
        WeekBars.Day(id: 5, letter: "S", value: nil, accessibilityLabel: "Saturday"),
        WeekBars.Day(id: 6, letter: "S", value: nil, accessibilityLabel: "Sunday"),
    ]

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
