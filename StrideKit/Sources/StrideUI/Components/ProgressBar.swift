import SwiftUI
import StrideKit

/// A thin horizontal progress bar. Turns `success` once full unless a tint is given.
public struct ProgressBar: View {
    let progress: Double
    let tint: Color?
    let height: CGFloat

    public init(progress: Double, tint: Color? = nil, height: CGFloat = 8) {
        self.progress = progress
        self.tint = tint
        self.height = height
    }

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.surfaceSunken)
                Capsule()
                    .fill(tint ?? (progress >= 1 ? Color.success : Color.track))
                    .frame(width: max(geo.size.width * min(max(progress, 0), 1), progress > 0 ? height : 0))
            }
        }
        .frame(height: height)
        .animation(.snappy, value: progress)
        .accessibilityElement()
        .accessibilityValue("\(Int((min(max(progress, 0), 1) * 100).rounded())) percent")
    }
}

public extension Shoe {
    /// The shoe's color from the design system's shoe palette.
    var color: Color { Self.colors[min(max(colorIndex, 0), Self.colors.count - 1)] }

    /// Colors a shoe can be tagged with, distinct in light and dark mode.
    static let colors: [Color] = [
        Color(light: 0x1D5FC4, dark: 0x74AEFF, watch: 0x74AEFF), // blue
        Color(light: 0xC8401F, dark: 0xFF6B47, watch: 0xFF6B47), // orange
        Color(light: 0x1E7A4C, dark: 0x4CC38A, watch: 0x4CC38A), // green
        Color(light: 0x7B3FB8, dark: 0xB58CF0, watch: 0xB58CF0), // purple
        Color(light: 0x5A6270, dark: 0x9BA5B3, watch: 0x9BA5B3), // gray
        Color(light: 0xB07400, dark: 0xF2B53A, watch: 0xF2B53A), // yellow
        Color(light: 0xB8336A, dark: 0xF07AA8, watch: 0xF07AA8), // pink
        Color(light: 0x12161C, dark: 0xF2F4F0, watch: 0xFFFFFF), // ink
    ]

    static let colorNames = ["Blue", "Orange", "Green", "Purple", "Gray", "Yellow", "Pink", "Black"]
}
