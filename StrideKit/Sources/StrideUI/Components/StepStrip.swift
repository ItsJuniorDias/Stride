import SwiftUI
import StrideKit

public extension WorkoutStep.Kind {
    /// The step's color in workout strips, legends and the live step card: warm-up and cool-down
    /// gray (zone 1), runs yellow (zone 4), recoveries blue (zone 2). Always pair it with the words.
    var color: Color {
        switch self {
        case .warmup, .cooldown: Palette.zone1
        case .run: Palette.zone4
        case .recover: Palette.zone2
        }
    }
}

/// A workout at a glance: one segment per step, as wide as its (estimated) time, in the step's
/// color. `.flat` is the thin strip in lists and the run setup (6–8pt); `.shaped` is the tall preview
/// in the plan and the builder (28–32pt) and on the watch (10pt), runs full height, warm-up and
/// cool-down half, recoveries a third. Pass `currentStep` during a run: done steps keep their color,
/// the current one fills to `currentProgress`, later ones are `line` gray.
///
/// Replaces the app's `WorkoutShapeBar`.
public struct StepStrip: View {
    public enum Style: Sendable {
        case flat, shaped
    }

    let kinds: [WorkoutStep.Kind]
    let durations: [TimeInterval]
    let style: Style
    let height: CGFloat
    let currentStep: Int?
    let currentProgress: Double
    let label: String?

    /// - Parameters:
    ///   - durations: seconds per step, e.g. `WorkoutEstimate(steps:paces:).stepDurations`.
    ///   - accessibilityLabel: what VoiceOver reads, e.g. ``summary(of:unit:)``. Without one the strip
    ///     is hidden from VoiceOver, for rows whose text already describes the workout.
    public init(steps: [WorkoutStep], durations: [TimeInterval], style: Style = .flat, height: CGFloat = 8,
                currentStep: Int? = nil, currentProgress: Double = 0, accessibilityLabel: String? = nil) {
        self.kinds = steps.map(\.kind)
        self.durations = durations
        self.style = style
        self.height = height
        self.currentStep = currentStep
        self.currentProgress = currentProgress
        self.label = accessibilityLabel
    }

    /// Estimates each step's time from the runner's paces, or typical ones without them.
    public init(steps: [WorkoutStep], paces: TrainingPaces? = nil, style: Style = .flat, height: CGFloat = 8,
                currentStep: Int? = nil, currentProgress: Double = 0, accessibilityLabel: String? = nil) {
        let estimate = paces.map { WorkoutEstimate(steps: steps, paces: $0) } ?? WorkoutEstimate(steps: steps)
        self.init(steps: steps, durations: estimate.stepDurations, style: style, height: height,
                  currentStep: currentStep, currentProgress: currentProgress, accessibilityLabel: accessibilityLabel)
    }

    public var body: some View {
        GeometryReader { geo in
            let widths = segmentWidths(in: geo.size.width)
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(kinds.indices, id: \.self) { index in
                    segment(at: index)
                        .frame(width: widths[index], height: segmentHeight(kinds[index]))
                }
            }
            .frame(width: geo.size.width, height: height, alignment: .bottomLeading)
        }
        .frame(height: height)
        .animation(.snappy, value: currentStep)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label ?? "")
        .accessibilityHidden(label == nil)
    }

    private var gap: CGFloat { kinds.count > 24 ? 1 : 2 }

    /// Short steps keep a sliver; the long ones give up the room it takes.
    private func segmentWidths(in width: CGFloat) -> [CGFloat] {
        guard !kinds.isEmpty else { return [] }
        let available = max(width - gap * CGFloat(kinds.count - 1), 0)
        let values = kinds.indices.map { durations.indices.contains($0) ? max(durations[$0], 0) : 0 }
        let total = values.reduce(0, +)
        guard total > 0 else { return Array(repeating: available / CGFloat(kinds.count), count: kinds.count) }
        let minimum = min(currentStep == nil ? 2 : 3, available / CGFloat(kinds.count))
        let raw = values.map { CGFloat($0 / total) * available }
        let shortCount = raw.filter { $0 < minimum }.count
        let longTotal = raw.filter { $0 >= minimum }.reduce(0, +)
        let scale = longTotal > 0 ? max(available - CGFloat(shortCount) * minimum, 0) / longTotal : 0
        return raw.map { $0 < minimum ? minimum : $0 * scale }
    }

    private func segmentHeight(_ kind: WorkoutStep.Kind) -> CGFloat {
        guard style == .shaped else { return height }
        switch kind {
        case .run: return height
        case .warmup, .cooldown: return height * 0.5
        case .recover: return height * 0.34
        }
    }

    @ViewBuilder private func segment(at index: Int) -> some View {
        let kind = kinds[index]
        let shape = RoundedRectangle(cornerRadius: min(height >= 20 ? 4 : 2, segmentHeight(kind) / 2))
        if let currentStep {
            if index < currentStep {
                shape.fill(kind.color)
            } else if index == currentStep {
                shape.fill(Color.line)
                    .overlay(alignment: .leading) {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(kind.color)
                                .frame(width: geo.size.width * min(max(currentProgress, 0), 1))
                        }
                    }
                    .clipShape(shape)
            } else {
                shape.fill(Color.line)
            }
        } else {
            shape.fill(kind.color)
        }
    }

    /// "10 min warm-up, 5 runs of 800 m with 2 min recoveries, 5 min cool-down", for VoiceOver.
    public nonisolated static func summary(of steps: [WorkoutStep], unit: UnitSystem) -> String {
        guard let blueprint = WorkoutBlueprint(steps: steps) else {
            let runs = steps.filter { $0.kind == .run }.count
            return "\(steps.count) steps, \(runs) \(runs == 1 ? "run" : "runs")"
        }
        var parts: [String] = []
        if let warmup = blueprint.warmup {
            parts.append("\(WorkoutBlueprint.text(for: warmup, unit: unit)) warm-up")
        }
        let work = WorkoutBlueprint.text(for: blueprint.work, unit: unit)
        if blueprint.repeats > 1 {
            var main = "\(blueprint.repeats) runs of \(work)"
            if let recovery = blueprint.recovery {
                main += " with \(WorkoutBlueprint.text(for: recovery, unit: unit)) recoveries"
            }
            parts.append(main)
        } else {
            parts.append("\(work) run")
        }
        if let cooldown = blueprint.cooldown {
            parts.append("\(WorkoutBlueprint.text(for: cooldown, unit: unit)) cool-down")
        }
        return parts.joined(separator: ", ")
    }
}

/// The key under a ``StepStrip``: 8pt swatches with "Warm-up, cool-down", "Run", "Recover". Hidden
/// from VoiceOver, since the strip's label says the same.
public struct StepLegend: View {
    let warmUpTitle: String
    let font: Font
    let spacing: CGFloat

    /// - Parameters:
    ///   - warmUpTitle: "Warm-up" where the workout shown has no cool-down worth naming.
    ///   - font: 13pt medium in lists; the run setup panel uses `.caption2.weight(.semibold)`.
    public init(warmUpTitle: String = "Warm-up, cool-down", font: Font = .footnote.weight(.medium),
                spacing: CGFloat = Space.x4) {
        self.warmUpTitle = warmUpTitle
        self.font = font
        self.spacing = spacing
    }

    public var body: some View {
        HStack(spacing: spacing) {
            item(WorkoutStep.Kind.warmup.color, warmUpTitle)
            item(WorkoutStep.Kind.run.color, WorkoutStep.Kind.run.title)
            item(WorkoutStep.Kind.recover.color, WorkoutStep.Kind.recover.title)
        }
        .font(font)
        .foregroundStyle(.inkMuted)
        .lineLimit(1)
        .accessibilityHidden(true)
    }

    private func item(_ color: Color, _ title: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
        }
    }
}
