import SwiftUI

/// Single-select capsule for run type, target distance, surface and similar choices.
public struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    public init(_ title: String, isSelected: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, Space.x4)
                .frame(minHeight: 36)
                .foregroundStyle(isSelected ? Color.onTrack : Color.ink)
                .background {
                    if isSelected {
                        Capsule().fill(Color.track)
                    } else {
                        Capsule().strokeBorder(Color.lineStrong, lineWidth: 1.5)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .sensoryFeedback(.selection, trigger: isSelected)
    }
}

/// Small read-only status capsule. The word always states the state; the dot only reinforces it.
public struct StatusChip: View {
    let title: String
    let indicator: Color?
    let background: Color

    public init(_ title: String, indicator: Color? = nil, background: Color = .surfaceRaised) {
        self.title = title
        self.indicator = indicator
        self.background = background
    }

    public var body: some View {
        HStack(spacing: Space.x2) {
            if let indicator {
                Circle().fill(indicator).frame(width: 8, height: 8)
            }
            Text(title).font(.caption.weight(.medium))
        }
        .foregroundStyle(.ink)
        .padding(.horizontal, Space.x3)
        .frame(minHeight: 28)
        .background(background, in: Capsule())
    }
}
