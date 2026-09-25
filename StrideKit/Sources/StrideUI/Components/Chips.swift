import SwiftUI

/// Single-select capsule for run type, target distance, surface and similar choices. An optional
/// `tag` (e.g. PRO) follows the title while the chip isn't selected.
public struct SelectableChip: View {
    let title: String
    let isSelected: Bool
    let tag: String?
    let action: () -> Void

    public init(_ title: String, isSelected: Bool, tag: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.tag = tag
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: Space.x2) {
                Text(title)
                if let tag, !isSelected { TagBadge(tag) }
            }
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

/// Small uppercase tag beside a title: PRO, BEST VALUE. Outlined in the brand color on a raised
/// fill, so it reads on cards, form rows and the glass run panel without competing with the one
/// filled action on the screen.
public struct TagBadge: View {
    let title: String

    public init(_ title: String) {
        self.title = title
    }

    public var body: some View {
        Text(title)
            .font(.caption2.weight(.bold))
            .tracking(0.6)
            .textCase(.uppercase)
            .foregroundStyle(.track)
            .lineLimit(1)
            .padding(.horizontal, Space.x2)
            .frame(minHeight: 20)
            .background(Color.surfaceRaised, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.track, lineWidth: 1))
            .fixedSize()
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
