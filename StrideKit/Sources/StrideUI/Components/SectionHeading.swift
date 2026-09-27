import SwiftUI

/// How a ``SectionHeading`` title looks.
public enum SectionHeadingStyle: Sendable {
    /// 17pt semibold ink: Home, Plans, the run summary and detail.
    case title
    /// Small uppercase muted label, inset 4pt: Profile, Shoes, Friends, Challenges.
    case overline
}

/// The title above a card or a group of rows, with an optional muted detail after a middle dot
/// (`detail: "this week"` reads "Friends · this week") and an optional link, caption or small control
/// at the trailing end, on the same baseline. The title is a VoiceOver header.
public struct SectionHeading<Trailing: View>: View {
    let title: String
    let detail: String?
    let style: SectionHeadingStyle
    let trailing: Trailing

    public init(_ title: String, detail: String? = nil, style: SectionHeadingStyle = .title,
                @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.detail = detail
        self.style = style
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
            heading
                .accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .padding(.leading, style == .overline ? Space.x1 : 0)
    }

    @ViewBuilder private var heading: some View {
        switch style {
        case .title:
            if let detail {
                Text("\(Text(title).fontWeight(.semibold).foregroundStyle(.ink)) \(Text(verbatim: "· \(detail)").foregroundStyle(.inkMuted))")
                    .font(.body)
            } else {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.ink)
            }
        case .overline:
            Text(detail.map { "\(title) · \($0)" } ?? title)
                .metricLabelStyle()
        }
    }
}

public extension SectionHeading where Trailing == EmptyView {
    init(_ title: String, detail: String? = nil, style: SectionHeadingStyle = .title) {
        self.init(title, detail: detail, style: style) { EmptyView() }
    }
}

public extension SectionHeading where Trailing == Text {
    /// A muted caption at the trailing end: "Avg 5'45" /km", "Swipe a workout to delete it".
    init(_ title: String, detail: String? = nil, style: SectionHeadingStyle = .title, caption: String) {
        self.init(title, detail: detail, style: style) {
            Text(caption)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
        }
    }
}

// MARK: - Links

/// A text link in the data color: "All runs", "See all", "Make default". Optionally a leading
/// symbol ("Test voice") or a trailing chevron ("All weeks and sessions").
public struct LinkButton: View {
    let title: String
    let systemImage: String?
    let showsChevron: Bool
    let action: () -> Void

    public init(_ title: String, systemImage: String? = nil, showsChevron: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.showsChevron = showsChevron
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            LinkLabel(title, systemImage: systemImage, showsChevron: showsChevron)
        }
        .buttonStyle(.strideLink)
    }
}

/// The label of a ``LinkButton``, for a `NavigationLink` styled with `.buttonStyle(.strideLink)`.
public struct LinkLabel: View {
    let title: String
    let systemImage: String?
    let showsChevron: Bool

    public init(_ title: String, systemImage: String? = nil, showsChevron: Bool = false) {
        self.title = title
        self.systemImage = systemImage
        self.showsChevron = showsChevron
    }

    public var body: some View {
        HStack(spacing: Space.x1) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.footnote.weight(.semibold))
                    .accessibilityHidden(true)
            }
            Text(title)
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .accessibilityHidden(true)
            }
        }
    }
}

/// 15pt semibold `lane` text, at least 44pt tall. Works on `Button` and `NavigationLink`; a label that
/// sets its own font (17pt "Save earlier runs too") keeps it.
public struct StrideLinkButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        StrideLinkBody(configuration: configuration)
    }
}

private struct StrideLinkBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(isEnabled ? Color.lane : Color.inkMuted)
            .frame(minHeight: Dimension.hitMin)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.55 : 1)
    }
}

public extension ButtonStyle where Self == StrideLinkButtonStyle {
    static var strideLink: StrideLinkButtonStyle { StrideLinkButtonStyle() }
}
