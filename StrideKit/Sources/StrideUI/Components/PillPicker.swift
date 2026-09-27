import SwiftUI

/// Height and fit of a ``PillPicker``.
public enum PillPickerSize: Sendable {
    /// 44pt track with 36pt pills, filling the width: the Progress period, the workout builder.
    case regular
    /// 48pt track with 40pt pills and a soft shadow on the selection, filling the width: onboarding units.
    case large
    /// 36pt track with 32pt pills, as wide as its labels: units on Profile, the Friends period.
    case compact

    var pillHeight: CGFloat {
        switch self {
        case .regular: 36
        case .large: 40
        case .compact: 32
        }
    }

    var inset: CGFloat { self == .compact ? 2 : 4 }

    /// Added above and below each pill so the tap target reaches 44pt.
    var hitPadding: CGFloat { (Dimension.hitMin - pillHeight) / 2 }
}

/// The app's segmented control: pills on a `surfaceRaised` (or, inside a raised card,
/// `surfaceSunken`) capsule, the selected one on `line` with ink text, the others muted. The
/// selection slides between pills and ticks with a selection haptic.
///
///     PillPicker("Period", selection: $period, options: Period.allCases) { $0.title }
public struct PillPicker<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [Value]
    let size: PillPickerSize
    let background: Color
    let label: (Value) -> String
    @Namespace private var namespace

    public init(_ title: String, selection: Binding<Value>, options: [Value], size: PillPickerSize = .regular,
                background: Color = .surfaceRaised, label: @escaping (Value) -> String) {
        self.title = title
        self._selection = selection
        self.options = options
        self.size = size
        self.background = background
        self.label = label
    }

    public var body: some View {
        HStack(spacing: size == .compact ? 0 : Space.x1) {
            ForEach(options, id: \.self) { option in
                pill(option)
            }
        }
        .padding(size.inset)
        .background(background, in: Capsule())
        .fixedSize(horizontal: size == .compact, vertical: false)
        .sensoryFeedback(.selection, trigger: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }

    private func pill(_ option: Value) -> some View {
        let isSelected = option == selection
        return Button {
            withAnimation(.snappy(duration: 0.25)) { selection = option }
        } label: {
            Text(label(option))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isSelected ? Color.ink : Color.inkMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, size == .compact ? 14 : Space.x2)
                .frame(maxWidth: size == .compact ? nil : CGFloat.infinity)
                .frame(height: size.pillHeight)
                .background {
                    if isSelected {
                        Capsule()
                            .fill(Color.line)
                            .shadow(color: .black.opacity(size == .large ? 0.3 : 0), radius: 1.5, y: 1)
                            .matchedGeometryEffect(id: "selection", in: namespace)
                    }
                }
                .padding(.vertical, size.hitPadding)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, -size.hitPadding)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
