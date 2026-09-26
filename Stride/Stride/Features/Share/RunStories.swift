import SwiftUI
import StrideKit
import StrideUI

/// What a share image shows about a run, taken from the run once so rendering never touches SwiftData.
struct ShareRun: Equatable {
    var title: String
    var date: Date
    var distance: Double
    var duration: TimeInterval
    var elevationGain: Double
    var coordinates: [Coordinate]
    var unit: UnitSystem

    init(title: String, date: Date, distance: Double, duration: TimeInterval, elevationGain: Double,
         coordinates: [Coordinate], unit: UnitSystem) {
        self.title = title
        self.date = date
        self.distance = distance
        self.duration = duration
        self.elevationGain = elevationGain
        self.coordinates = coordinates
        self.unit = unit
    }

    init(run: Run, unit: UnitSystem) {
        self.init(title: run.title, date: run.startDate, distance: run.distance, duration: run.duration,
                  elevationGain: run.elevationGain, coordinates: run.preview, unit: unit)
    }

    var distanceText: String { RunFormat.distance(distance, unit: unit) }
    var timeText: String { RunFormat.duration(duration) }
    var paceText: String { RunFormat.pace(RunFormat.paceSeconds(distance: distance, duration: duration, unit: unit)) }
    var elevationText: String { "\(Int(unit.elevation(fromMeters: elevationGain).rounded()))" }
    var dateText: String { date.formatted(.dateTime.day().month(.abbreviated).year()) }
    var hasRoute: Bool { coordinates.count > 1 }
}

/// The share images, all Instagram Stories size (9:16, 1080 × 1920 when rendered).
enum StoryTemplate: String, CaseIterable, Identifiable {
    case card, route, photo, sticker

    var id: Self { self }

    var title: String {
        switch self {
        case .card: "Card"
        case .route: "Route"
        case .photo: "Photo"
        case .sticker: "Sticker"
        }
    }

    /// The sticker has no background: Instagram places it over the runner's own photo or video.
    var isTransparent: Bool { self == .sticker }
}

/// Fixed Dark-theme values of the design tokens: share images look the same whichever theme the
/// runner uses.
private enum StoryInk {
    static let surface = Color(red: 0x10 / 255, green: 0x14 / 255, blue: 0x19 / 255)
    static let deep = Color(red: 0x0B / 255, green: 0x0E / 255, blue: 0x12 / 255)
    static let grid = Color(red: 0x16 / 255, green: 0x1B / 255, blue: 0x22 / 255)
    static let track = Color(red: 1, green: 0x6B / 255, blue: 0x47 / 255)
    static let ink = Color(red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF0 / 255)
    static let muted = Color(red: 0x9B / 255, green: 0xA5 / 255, blue: 0xB3 / 255)
    static let line = Color(red: 0x3A / 255, green: 0x44 / 255, blue: 0x52 / 255)
}

/// Story canvas in points; rendered at 3× for 1080 × 1920. Instagram covers roughly the top 56 pt
/// and bottom 116 pt with its own controls, so nothing important sits there.
enum StoryLayout {
    static let size = CGSize(width: 360, height: 640)
    static let topSafe: CGFloat = 56
    static let bottomSafe: CGFloat = 116
}

// MARK: - Pieces

private struct StoryWordmark: View {
    var size: CGFloat = 19

    var body: some View {
        Text("STRIDE")
            .font(.system(size: size, weight: .black).width(.expanded))
            .tracking(size * 0.1)
            .foregroundStyle(StoryInk.track)
    }
}

/// The route with a hollow start mark and a filled finish mark.
private struct StoryRoute: View {
    let coordinates: [Coordinate]
    var color: Color = StoryInk.track
    var lineWidth: CGFloat = 6
    var startFill: Color = StoryInk.surface
    var glow = false

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size).insetBy(dx: lineWidth, dy: lineWidth)
            let points = RouteShape.points(coordinates, in: rect)
            ZStack {
                RouteShape(coordinates: coordinates)
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                    .padding(lineWidth)
                if let first = points.first, let last = points.last {
                    Circle()
                        .fill(startFill)
                        .overlay(Circle().stroke(color, lineWidth: max(2, lineWidth * 0.6)))
                        .frame(width: lineWidth * 2.2, height: lineWidth * 2.2)
                        .position(first)
                    Circle()
                        .fill(color)
                        .frame(width: lineWidth * 1.8, height: lineWidth * 1.8)
                        .position(last)
                }
            }
            .shadow(color: glow ? color.opacity(0.55) : .clear, radius: glow ? 10 : 0)
        }
    }
}

/// A route, or the running figure for a run without one (treadmill, manual).
private struct StoryRouteOrFigure: View {
    let share: ShareRun
    var color: Color = StoryInk.track
    var lineWidth: CGFloat = 6
    var startFill: Color = StoryInk.surface
    var glow = false

    var body: some View {
        if share.hasRoute {
            StoryRoute(coordinates: share.coordinates, color: color, lineWidth: lineWidth, startFill: startFill, glow: glow)
        } else {
            Image(systemName: "figure.run")
                .resizable()
                .scaledToFit()
                .padding(24)
                .foregroundStyle(color)
        }
    }
}

private struct StoryStat: View {
    let label: String
    let value: String
    var unit: String?
    var labelColor: Color = StoryInk.muted
    var valueColor: Color = StoryInk.ink
    var size: CGFloat = 24

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(labelColor)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: size, weight: .bold).width(.expanded))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(labelColor)
                        .fixedSize()
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StoryStats: View {
    let share: ShareRun
    var labelColor: Color = StoryInk.muted
    var valueColor: Color = StoryInk.ink
    var size: CGFloat = 24

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            StoryStat(label: "Time", value: share.timeText, labelColor: labelColor, valueColor: valueColor, size: size)
            StoryStat(label: "Avg pace", value: share.paceText, unit: share.unit.paceSymbol,
                      labelColor: labelColor, valueColor: valueColor, size: size)
            StoryStat(label: "Elevation", value: share.elevationText, unit: share.unit.elevationSymbol,
                      labelColor: labelColor, valueColor: valueColor, size: size)
        }
    }
}

private struct StoryDistance: View {
    let share: ShareRun
    var size: CGFloat
    var color: Color = StoryInk.ink
    var unitColor: Color = StoryInk.muted

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(share.distanceText)
                .font(.system(size: size, weight: .black).width(.expanded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .foregroundStyle(color)
            Text(share.unit.distanceSymbol)
                .font(.system(size: size * 0.28, weight: .semibold).width(.expanded))
                .foregroundStyle(unitColor)
        }
    }
}

// MARK: - Templates

/// The card: route above, the distance large, then time, pace and elevation.
struct StoryCardView: View {
    let share: ShareRun

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                StoryWordmark()
                Spacer()
                Text(share.dateText).font(.system(size: 14)).foregroundStyle(StoryInk.muted)
            }
            StoryRouteOrFigure(share: share)
                .frame(width: 190, height: 175)
                .frame(maxWidth: .infinity)
                .padding(.top, 30)
            Spacer(minLength: 16)
            Text(share.title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(StoryInk.muted)
                .lineLimit(1)
            StoryDistance(share: share, size: 88)
                .padding(.top, 6)
            Rectangle().fill(StoryInk.line).frame(height: 1).padding(.vertical, 18)
            StoryStats(share: share)
        }
        .padding(.horizontal, 24)
        .padding(.top, StoryLayout.topSafe)
        .padding(.bottom, StoryLayout.bottomSafe)
        .frame(width: StoryLayout.size.width, height: StoryLayout.size.height)
        .background(StoryInk.surface)
    }
}

/// The route as the hero, glowing over a faint street grid, with the numbers under it.
struct StoryRouteView: View {
    let share: ShareRun

    var body: some View {
        ZStack(alignment: .topLeading) {
            StoryInk.deep
            Canvas { context, size in
                var grid = Path()
                for x in stride(from: 20.0, to: size.width, by: 44) {
                    grid.move(to: CGPoint(x: x, y: 0))
                    grid.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 30.0, to: size.height, by: 44) {
                    grid.move(to: CGPoint(x: 0, y: y))
                    grid.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(grid, with: .color(StoryInk.grid), lineWidth: 1)
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    StoryWordmark()
                    Spacer()
                    Text(share.dateText).font(.system(size: 14)).foregroundStyle(StoryInk.muted)
                }
                StoryRouteOrFigure(share: share, lineWidth: 7, startFill: StoryInk.deep, glow: true)
                    .frame(maxWidth: .infinity)
                    .frame(height: 280)
                    .padding(.top, 34)
                Spacer(minLength: 12)
                StoryDistance(share: share, size: 72)
                StoryStats(share: share, size: 22)
                    .padding(.top, 14)
            }
            .padding(.horizontal, 24)
            .padding(.top, StoryLayout.topSafe)
            .padding(.bottom, StoryLayout.bottomSafe)
        }
        .frame(width: StoryLayout.size.width, height: StoryLayout.size.height)
    }
}

/// The runner's photo with soft shades top and bottom so the numbers read on any picture.
struct StoryPhotoView: View {
    let share: ShareRun
    let photo: UIImage?

    private let light = Color.white.opacity(0.85)

    var body: some View {
        ZStack {
            StoryInk.surface
            if let photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: StoryLayout.size.width, height: StoryLayout.size.height)
                    .clipped()
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 36, weight: .semibold))
                    Text("Choose a photo")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(StoryInk.muted)
                .offset(y: -60)
            }
            VStack(spacing: 0) {
                LinearGradient(colors: [.black.opacity(0.55), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 170)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 360)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    StoryWordmark()
                    Spacer()
                    Text(share.dateText).font(.system(size: 14)).foregroundStyle(light)
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(share.title.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(1.3)
                            .foregroundStyle(light)
                            .lineLimit(1)
                        StoryDistance(share: share, size: 76, color: .white, unitColor: light)
                    }
                    Spacer(minLength: 8)
                    if share.hasRoute {
                        StoryRoute(coordinates: share.coordinates, color: .white, lineWidth: 5, startFill: .clear)
                            .frame(width: 86, height: 80)
                            .opacity(0.9)
                    }
                }
                StoryStats(share: share, labelColor: light, valueColor: .white, size: 22)
            }
            .padding(.horizontal, 24)
            .padding(.top, StoryLayout.topSafe)
            .padding(.bottom, StoryLayout.bottomSafe)
        }
        .frame(width: StoryLayout.size.width, height: StoryLayout.size.height)
    }
}

/// The sticker alone, on a transparent background: Instagram places it over the runner's own
/// photo or video, so it carries a soft shadow to read on anything.
struct StoryStickerView: View {
    let share: ShareRun

    var body: some View {
        VStack(spacing: 10) {
            StoryRouteOrFigure(share: share, lineWidth: 8, startFill: .white)
                .frame(width: 150, height: 138)
            StoryDistance(share: share, size: 80, color: .white, unitColor: .white)
                .padding(.top, 6)
            Text("\(share.timeText) · \(share.paceText) \(share.unit.paceSymbol)")
                .font(.system(size: 20, weight: .bold).width(.expanded))
                .monospacedDigit()
                .foregroundStyle(.white)
            StoryWordmark(size: 15)
                .padding(.top, 4)
        }
        .shadow(color: .black.opacity(0.35), radius: 7, y: 1)
        .padding(20)
        .frame(width: 320)
    }
}

/// The sticker on a checkerboard, for the share sheet's preview only.
struct StoryStickerPreview: View {
    let share: ShareRun

    var body: some View {
        ZStack(alignment: .topLeading) {
            Canvas { context, size in
                let cell: CGFloat = 12
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.125, green: 0.141, blue: 0.169)))
                for row in 0..<Int(size.height / cell) + 1 {
                    for column in 0..<Int(size.width / cell) + 1 where (row + column).isMultiple(of: 2) {
                        let rect = CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                        context.fill(Path(rect), with: .color(Color(red: 0.165, green: 0.184, blue: 0.216)))
                    }
                }
            }
            StoryStickerView(share: share)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text("TRANSPARENT")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1.3)
                .foregroundStyle(StoryInk.muted)
                .padding(18)
        }
        .frame(width: StoryLayout.size.width, height: StoryLayout.size.height)
    }
}

// MARK: - Rendering

enum StoryRenderer {
    /// The template as the image to share: 1080 × 1920 for the backgrounds, the sticker at its own
    /// size with a transparent background.
    @MainActor
    static func image(for template: StoryTemplate, share: ShareRun, photo: UIImage?) -> UIImage? {
        switch template {
        case .card: render(StoryCardView(share: share), opaque: true)
        case .route: render(StoryRouteView(share: share), opaque: true)
        case .photo: render(StoryPhotoView(share: share, photo: photo), opaque: true)
        case .sticker: render(StoryStickerView(share: share), opaque: false)
        }
    }

    @MainActor
    private static func render(_ view: some View, opaque: Bool) -> UIImage? {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 3
        renderer.isOpaque = opaque
        return renderer.uiImage
    }
}

#Preview("Card") {
    StoryCardView(share: .preview)
}

#Preview("Route") {
    StoryRouteView(share: .preview)
}

#Preview("Sticker") {
    StoryStickerPreview(share: .preview)
}

extension ShareRun {
    /// A made-up evening run for previews.
    static var preview: ShareRun {
        ShareRun(title: "Evening Run", date: .now, distance: 8_420, duration: 2_658, elevationGain: 86,
                 coordinates: (0..<60).map { i in
                     Coordinate(latitude: sin(Double(i) / 9.5) * 0.004, longitude: cos(Double(i) / 9.5) * 0.006)
                 },
                 unit: .metric)
    }
}
