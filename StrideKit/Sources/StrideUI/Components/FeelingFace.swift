import SwiftUI
import StrideKit

/// The line face for how a run felt, drawn to the approved design (SF Symbols has no set of moods):
/// a circle with two eyes and a mouth from a wide smile to a frown, and a small plus for Injured.
/// Strokes in the current foreground style. Decorative: the picker around it says the word.
public struct FeelingFace: View {
    let feeling: Feeling
    let size: CGFloat

    public init(_ feeling: Feeling, size: CGFloat = 26) {
        self.feeling = feeling
        self.size = size
    }

    public var body: some View {
        ZStack {
            FeelingFaceLines(feeling: feeling)
                .stroke(style: StrokeStyle(lineWidth: 2 * size / 24, lineCap: .round, lineJoin: .round))
            FeelingFaceEyes()
                .fill()
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// The face on a 24-point grid, scaled to fit.
private func faceTransform(for rect: CGRect) -> CGAffineTransform {
    let scale = min(rect.width, rect.height) / 24
    return CGAffineTransform(translationX: rect.midX - 12 * scale, y: rect.midY - 12 * scale)
        .scaledBy(x: scale, y: scale)
}

private struct FeelingFaceLines: Shape {
    let feeling: Feeling

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 3.5, y: 3.5, width: 17, height: 17))
        switch feeling {
        case .great:
            path.move(to: CGPoint(x: 8, y: 13.8))
            path.addLine(to: CGPoint(x: 16, y: 13.8))
            path.addCurve(to: CGPoint(x: 12, y: 17.2), control1: CGPoint(x: 15.5, y: 15.9), control2: CGPoint(x: 14, y: 17.2))
            path.addCurve(to: CGPoint(x: 8, y: 13.8), control1: CGPoint(x: 10, y: 17.2), control2: CGPoint(x: 8.5, y: 15.9))
            path.closeSubpath()
        case .good:
            path.move(to: CGPoint(x: 8.5, y: 14.5))
            path.addCurve(to: CGPoint(x: 12, y: 16.5), control1: CGPoint(x: 9.4, y: 15.8), control2: CGPoint(x: 10.6, y: 16.5))
            path.addCurve(to: CGPoint(x: 15.5, y: 14.5), control1: CGPoint(x: 13.4, y: 16.5), control2: CGPoint(x: 14.6, y: 15.8))
        case .okay:
            path.move(to: CGPoint(x: 9, y: 15.5))
            path.addLine(to: CGPoint(x: 15, y: 15.5))
        case .tough:
            path.move(to: CGPoint(x: 8.5, y: 16.8))
            path.addCurve(to: CGPoint(x: 12, y: 14.8), control1: CGPoint(x: 9.4, y: 15.5), control2: CGPoint(x: 10.6, y: 14.8))
            path.addCurve(to: CGPoint(x: 15.5, y: 16.8), control1: CGPoint(x: 13.4, y: 14.8), control2: CGPoint(x: 14.6, y: 15.5))
        case .injured:
            path.move(to: CGPoint(x: 8.5, y: 16.3))
            path.addCurve(to: CGPoint(x: 11.5, y: 16.3), control1: CGPoint(x: 9.5, y: 15.5), control2: CGPoint(x: 10.5, y: 15.5))
            path.addCurve(to: CGPoint(x: 14.5, y: 16.3), control1: CGPoint(x: 12.5, y: 17.1), control2: CGPoint(x: 13.5, y: 17.1))
            path.move(to: CGPoint(x: 20, y: 1.8))
            path.addLine(to: CGPoint(x: 20, y: 6.2))
            path.move(to: CGPoint(x: 17.8, y: 4))
            path.addLine(to: CGPoint(x: 22.2, y: 4))
        }
        return path.applying(faceTransform(for: rect))
    }
}

private struct FeelingFaceEyes: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addEllipse(in: CGRect(x: 7.6, y: 8.6, width: 2.8, height: 2.8))
        path.addEllipse(in: CGRect(x: 13.6, y: 8.6, width: 2.8, height: 2.8))
        return path.applying(faceTransform(for: rect))
    }
}
