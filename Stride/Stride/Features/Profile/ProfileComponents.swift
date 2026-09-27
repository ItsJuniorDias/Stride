import SwiftUI
import StrideKit
import StrideUI

// Pieces shared by Profile and Friends: settings rows, the goal steppers, the check chips and the
// name editor.

/// A settings row in a ``GroupedCard``: an optional 36pt sunken icon, a 17pt title with an optional
/// 13pt subtitle, and a switch in the brand color. A native `Toggle`, so VoiceOver reads the title
/// and subtitle as the switch's label.
struct SettingToggleRow: View {
    let title: String
    let subtitle: String?
    let symbol: String?
    @Binding var isOn: Bool

    init(_ title: String, subtitle: String? = nil, symbol: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self.symbol = symbol
        self._isOn = isOn
    }

    var body: some View {
        HStack(spacing: Space.x3) {
            if let symbol {
                SettingIcon(symbol)
            }
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(.inkMuted)
                    }
                }
            }
            .tint(.track)
        }
        .padding(.vertical, Space.x3)
        .padding(.horizontal, Space.x4)
        .frame(minHeight: subtitle == nil ? 52 : 64)
    }
}

/// The 36pt rounded sunken icon that leads a settings row.
struct SettingIcon: View {
    let symbol: String

    init(_ symbol: String) {
        self.symbol = symbol
    }

    var body: some View {
        IconBadge(symbol, style: .sunken, size: 36, corner: .rounded)
    }
}

/// An outlined capsule label for a secondary action that sits in a row: "Manage", "Share invite".
/// Wrap it in a `Button` or `ShareLink`; the tap area reaches 44pt.
struct OutlineCapsuleLabel: View {
    let title: String
    var systemImage: String?
    /// 36pt in a row of text, 44pt on its own.
    var height: CGFloat = 36
    var horizontalPadding: CGFloat = 14

    var body: some View {
        HStack(spacing: Space.x2) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 15, weight: .semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
                .lineLimit(1)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.ink)
        .padding(.horizontal, horizontalPadding)
        .frame(height: height)
        .overlay(Capsule().strokeBorder(Color.lineStrong, lineWidth: 1.5))
        .frame(minHeight: Dimension.hitMin)
        .contentShape(Rectangle())
    }
}

/// A goal or body setting on its own raised card: an uppercase label with minus and plus buttons,
/// the value in SF Pro Expanded, a meter under it and a caption. The buttons repeat while held.
/// VoiceOver reads the value as one adjustable element (swipe up or down to change it), and the
/// buttons stay available for Voice Control.
struct GoalStepperCard<Meter: View>: View {
    let title: String
    let accessibilityName: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let caption: String
    let lowerLabel: String
    let raiseLabel: String
    let meter: Meter

    init(_ title: String, accessibilityName: String, value: Binding<Double>, in range: ClosedRange<Double>, step: Double,
         unit: String, caption: String, lowerLabel: String, raiseLabel: String, @ViewBuilder meter: () -> Meter) {
        self.title = title
        self.accessibilityName = accessibilityName
        self._value = value
        self.range = range
        self.step = step
        self.unit = unit
        self.caption = caption
        self.lowerLabel = lowerLabel
        self.raiseLabel = raiseLabel
        self.meter = meter()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(title)
                    .metricLabelStyle()
                    .lineLimit(1)
                    .accessibilityHidden(true)
                Spacer(minLength: Space.x1)
                RoundIconButton("minus", accessibilityLabel: lowerLabel, style: .sunken, diameter: 32) { change(by: -step) }
                    .disabled(value <= range.lowerBound)
                RoundIconButton("plus", accessibilityLabel: raiseLabel, style: .sunken, diameter: 32) { change(by: step) }
                    .disabled(value >= range.upperBound)
            }
            .frame(height: Dimension.hitMin)
            .padding(.trailing, -Space.x2)
            .buttonRepeatBehavior(.enabled)

            HStack(alignment: .firstTextBaseline, spacing: Space.x1) {
                Text(valueText)
                    .font(.system(size: 28, weight: .bold).width(.expanded))
                    .monospacedDigit()
                    .foregroundStyle(.ink)
                    .contentTransition(.numericText(value: value))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(unit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.inkMuted)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.top, 2)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityName)
            .accessibilityValue("\(valueText) \(unit), \(caption)")
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: change(by: step)
                case .decrement: change(by: -step)
                @unknown default: break
                }
            }
            .accessibilitySortPriority(1)

            meter
                .padding(.top, 10)
                .accessibilityHidden(true)
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.inkMuted)
                .padding(.top, 6)
                .accessibilityHidden(true)
        }
        .padding(EdgeInsets(top: Space.x2, leading: 14, bottom: 14, trailing: 14))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
        .accessibilityElement(children: .contain)
        .animation(.snappy(duration: 0.2), value: value)
        .sensoryFeedback(.selection, trigger: value)
    }

    /// Whole numbers with grouping: "30", "1,000", "188".
    private var valueText: String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private func change(by delta: Double) {
        value = min(max(value + delta, range.lowerBound), range.upperBound)
    }
}

/// A toggle drawn as a chip: filled in the brand color with a check when on, outlined when off.
/// VoiceOver sees a native switch.
struct CheckChipToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(spacing: 6) {
                if configuration.isOn {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
                configuration.label
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(configuration.isOn ? Color.onTrack : Color.ink)
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .frame(height: 36)
            .background {
                if configuration.isOn {
                    Capsule().fill(Color.track)
                } else {
                    Capsule().strokeBorder(Color.lineStrong, lineWidth: 1.5)
                }
            }
            .frame(minHeight: Dimension.hitMin)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }
        }
    }
}

extension View {
    /// Edits the runner's name in an alert. Set `draft` to the current name before presenting;
    /// `save` gets the trimmed text.
    func nameEditor(isPresented: Binding<Bool>, draft: Binding<String>, save: @escaping (String) -> Void) -> some View {
        alert("Name friends see", isPresented: isPresented) {
            TextField("Your name", text: draft)
                .textContentType(.givenName)
                .textInputAutocapitalization(.words)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                save(draft.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        } message: {
            Text("Shown on your profile, and to friends who have your code.")
        }
    }
}
