import SwiftUI

/// A capsule meter on a sunken track: plan, goal and challenge progress, shoe wear, friends' weeks,
/// zone and split rows. Fills in the data color unless given a tint (a shoe's color, a zone color).
/// Optional extras from the Progress and Challenges designs:
/// - `marker`: a tick across the bar at a fraction (your usual week, the even pace), with an optional
///   caption above it;
/// - `band`: a range drawn inside the track (the replace-soon last 10% of a shoe) or as a thin bar
///   just below it (the safe-build range of the training load).
///
/// Unlike ``ProgressBar`` it doesn't turn `success` when full.
public struct TrackBar: View {
    public enum BandPlacement: Sendable {
        case inside, below
    }

    let progress: Double
    let tint: Color
    let height: CGFloat
    let track: Color
    let marker: Double?
    let markerLabel: String?
    let markerColor: Color
    let markerOutline: Color?
    let band: ClosedRange<Double>?
    let bandColor: Color
    let bandPlacement: BandPlacement

    private static let captionHeight: CGFloat = 18
    private static let bandGap: CGFloat = 4
    private static let bandHeight: CGFloat = 4

    /// - Parameters:
    ///   - progress: 0…1; values outside are clamped.
    ///   - track: `.surfaceSunken` on raised cards; `.surfaceRaised` on the plain background or a sunken well.
    ///   - markerOutline: a 2pt ring in the surface behind the bar, so the tick reads over the fill.
    public init(progress: Double, tint: Color = .lane, height: CGFloat = 8, track: Color = .surfaceSunken,
                marker: Double? = nil, markerLabel: String? = nil, markerColor: Color = .ink,
                markerOutline: Color? = .surfaceRaised,
                band: ClosedRange<Double>? = nil, bandColor: Color = Color.warning.opacity(0.28),
                bandPlacement: BandPlacement = .inside) {
        self.progress = progress
        self.tint = tint
        self.height = height
        self.track = track
        self.marker = marker
        self.markerLabel = markerLabel
        self.markerColor = markerColor
        self.markerOutline = markerOutline
        self.band = band
        self.bandColor = bandColor
        self.bandPlacement = bandPlacement
    }

    public var body: some View {
        let fraction = Self.clamp(progress)
        bar(fraction)
            .frame(height: height)
            .overlay { markerTick }
            .padding(.top, marker != nil && markerLabel != nil ? Self.captionHeight : 0)
            .overlay(alignment: .top) { markerCaption }
            .padding(.bottom, band != nil && bandPlacement == .below ? Self.bandGap + Self.bandHeight : 0)
            .overlay(alignment: .bottom) { bandBelow }
            .animation(.snappy, value: progress)
            .accessibilityElement()
            .accessibilityValue("\(Int((fraction * 100).rounded())) percent")
    }

    private func bar(_ fraction: Double) -> some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                if let band, bandPlacement == .inside {
                    Rectangle()
                        .fill(bandColor)
                        .frame(width: width * (Self.clamp(band.upperBound) - Self.clamp(band.lowerBound)))
                        .offset(x: width * Self.clamp(band.lowerBound))
                }
                Capsule()
                    .fill(tint)
                    .frame(width: fraction > 0 ? max(width * fraction, height) : 0)
            }
            .clipShape(Capsule())
        }
    }

    @ViewBuilder private var markerTick: some View {
        if let marker {
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(markerColor)
                    .frame(width: 3, height: height + 8)
                    .background {
                        if let markerOutline {
                            RoundedRectangle(cornerRadius: 3.5).fill(markerOutline).padding(-2)
                        }
                    }
                    .position(x: geo.size.width * Self.clamp(marker), y: geo.size.height / 2)
            }
        }
    }

    @ViewBuilder private var markerCaption: some View {
        if let marker, let markerLabel {
            GeometryReader { geo in
                Text(markerLabel)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.inkMuted)
                    .fixedSize()
                    .position(x: geo.size.width * Self.clamp(marker), y: Self.captionHeight / 2 - 3)
            }
            .frame(height: Self.captionHeight)
        }
    }

    @ViewBuilder private var bandBelow: some View {
        if let band, bandPlacement == .below {
            GeometryReader { geo in
                Capsule()
                    .fill(bandColor)
                    .frame(width: geo.size.width * (Self.clamp(band.upperBound) - Self.clamp(band.lowerBound)),
                           height: Self.bandHeight)
                    .offset(x: geo.size.width * Self.clamp(band.lowerBound))
            }
            .frame(height: Self.bandHeight)
        }
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

/// A row of short ``TrackBar``s, one per week of a plan: done weeks full, this week partly filled.
public struct SegmentedProgressBar: View {
    let fractions: [Double]
    let tint: Color
    let track: Color
    let height: CGFloat
    let spacing: CGFloat

    public init(fractions: [Double], tint: Color = .lane, track: Color = .surfaceSunken,
                height: CGFloat = 8, spacing: CGFloat = Space.x1) {
        self.fractions = fractions
        self.tint = tint
        self.track = track
        self.height = height
        self.spacing = spacing
    }

    /// `count` segments filled up to `progress` (0…count): 2.34 fills two and a third of the third.
    public init(count: Int, progress: Double, tint: Color = .lane, track: Color = .surfaceSunken,
                height: CGFloat = 8, spacing: CGFloat = Space.x1) {
        self.init(fractions: (0..<max(count, 0)).map { min(max(progress - Double($0), 0), 1) },
                  tint: tint, track: track, height: height, spacing: spacing)
    }

    public var body: some View {
        HStack(spacing: spacing) {
            ForEach(fractions.indices, id: \.self) { index in
                TrackBar(progress: fractions[index], tint: tint, height: height, track: track)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityValue("\(Int((overall * 100).rounded())) percent")
    }

    private var overall: Double {
        guard !fractions.isEmpty else { return 0 }
        return fractions.reduce(0) { $0 + min(max($1, 0), 1) } / Double(fractions.count)
    }
}
