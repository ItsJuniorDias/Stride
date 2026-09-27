import SwiftUI
import CoreLocation
import CoreText
import StrideKit
import StrideUI

/// The first launch on a device, as designed: what Stride is; the runner's name, unit and weekly
/// goal, with the week that goal suggests; location and Apple Health; and Apple Watch. Everything
/// can be changed later in Profile.
struct OnboardingView: View {
    /// Called once the last page is done; Stride Pro is offered after this.
    let onFinish: () -> Void

    @AppStorage(StrideSettings.userName) private var userName = ""
    @AppStorage(StrideSettings.unitSystem) private var unit: UnitSystem = .metric
    @AppStorage(StrideSettings.weeklyGoal) private var weeklyGoal = 20.0
    @AppStorage(StrideSettings.healthSave) private var healthSave = false
    @State private var page = Page.welcome
    /// Which way the last move went, so pages slide in from the matching side.
    @State private var movingForward = true
    @State private var location = LocationPermission()
    /// What Health answered, once asked.
    @State private var healthConnected: Bool?
    /// The bottom safe area: the home indicator, or the keyboard while it's up.
    @State private var bottomInset: CGFloat = 0
    @FocusState private var nameFocused: Bool
    /// The welcome headline, 34pt at the default text size.
    @ScaledMetric(relativeTo: .largeTitle) private var headlineSize: CGFloat = 34

    enum Page: Int, CaseIterable {
        case welcome, you, access, watch
    }

    /// The weekly goal, in the runner's unit, and its step.
    private static let goalRange: ClosedRange<Double> = 5...300
    private static let goalStep = 5.0

    var body: some View {
        VStack(spacing: 0) {
            topBar

            // One page at a time: a paged TabView could fall out of step with the buttons.
            ZStack {
                switch page {
                case .welcome: welcome
                case .you: you
                case .access: access
                case .watch: watch
                }
            }
            .id(page)
            .transition(.asymmetric(insertion: .move(edge: movingForward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: movingForward ? .leading : .trailing).combined(with: .opacity)))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()

            footer
        }
        .background {
            ZStack {
                Color.surface
                if page == .welcome {
                    BrandGlow(.blobs)
                        .transition(.opacity)
                }
            }
            .ignoresSafeArea()
        }
        .sensoryFeedback(.selection, trigger: page)
        .onGeometryChange(for: CGFloat.self) { $0.safeAreaInsets.bottom } action: { bottomInset = $0 }
    }

    /// The wordmark on the welcome page, a glass back button after it.
    private var topBar: some View {
        ZStack(alignment: .leading) {
            if page == .welcome {
                BrandLockup()
                    .transition(.opacity)
            } else {
                GlassIconButton("chevron.left", accessibilityLabel: "Back", action: back)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, minHeight: Dimension.hitMin, alignment: .leading)
        .padding(.horizontal, Space.x4)
    }

    private var footer: some View {
        VStack(spacing: Space.x4) {
            PageDots(count: Page.allCases.count, current: page.rawValue)
            Button(primaryTitle, action: next)
                .buttonStyle(.stridePrimary)
        }
        .padding(.horizontal, Space.x4)
        // Sits on the home indicator's area, as designed; keeps a margin without one, and over the keyboard.
        .padding(.bottom, bottomInset > 0 && !nameFocused ? 0 : Space.x4)
    }

    private var primaryTitle: String {
        switch page {
        case .welcome: "Get started"
        case .you, .access: "Continue"
        case .watch: "Start running"
        }
    }

    private func next() {
        nameFocused = false
        guard let following = Page(rawValue: page.rawValue + 1) else {
            onFinish()
            return
        }
        movingForward = true
        withAnimation(.snappy) { page = following }
    }

    private func back() {
        nameFocused = false
        guard let previous = Page(rawValue: page.rawValue - 1) else { return }
        movingForward = false
        withAnimation(.snappy) { page = previous }
    }

    // MARK: Welcome

    private var welcome: some View {
        ArtPage(art: "onboardingWelcome", zoom: 1.5, shift: 11, heights: 180...400, idealHeight: 326,
                bottomSpacing: 28) {
            VStack(alignment: .leading, spacing: 20) {
                Text("Every run, recorded and coached\(Text(verbatim: ".").foregroundStyle(Color.track))")
                    .font(.system(size: headlineSize, weight: .heavy).width(.expanded))
                    .tracking(-0.5)
                    .foregroundStyle(.ink)
                    .exactLineHeight(headlineSize * 38 / 34)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                VStack(alignment: .leading, spacing: 10) {
                    FeatureRow(symbol: "location", title: "GPS runs on iPhone or Apple Watch")
                    FeatureRow(symbol: "headphones", title: "Training plans with a coach in your ear")
                    FeatureRow(symbol: "chart.bar", title: "Weekly goals, streaks and records")
                }
            }
            .padding(.top, Space.x5)
        }
    }

    // MARK: You

    private var you: some View {
        PageBody(bottomSpacing: 20) { _ in
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "A little about you",
                           message: "So Stride greets you by name and measures the way you do.")
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: Space.x5) {
                    LabeledField("Name") { nameField }
                    LabeledField("Units") {
                        PillPicker("Units", selection: $unit, options: UnitSystem.allCases, size: .large) {
                            $0 == .metric ? "Kilometers" : "Miles"
                        }
                    }
                    LabeledField("Weekly goal") { goalCard }
                }
                .padding(.top, Space.x6)

                Spacer(minLength: Space.x5)

                Text("You can change any of this later in Profile.")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.inkMuted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var nameField: some View {
        TextField("Name", text: $userName, prompt: Text("Your name").foregroundStyle(Color.inkMuted))
            .font(.body)
            .foregroundStyle(.ink)
            .textContentType(.givenName)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
            .submitLabel(.done)
            .focused($nameFocused)
            .padding(.horizontal, Space.x4)
            .frame(maxWidth: .infinity, minHeight: Dimension.control, alignment: .leading)
            .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    /// The goal between round minus and plus buttons, then the week it suggests.
    private var goalCard: some View {
        let suggestion = WeekPlanSuggestion(weeklyGoal: weeklyGoal, unit: unit)
        return VStack(alignment: .leading, spacing: Space.x4) {
            HStack(spacing: Space.x3) {
                RoundIconButton("minus", accessibilityLabel: "Lower the goal", style: .outlined, diameter: 48) {
                    changeGoal(by: -Self.goalStep)
                }
                .disabled(weeklyGoal <= Self.goalRange.lowerBound)

                goalValue

                RoundIconButton("plus", accessibilityLabel: "Raise the goal", style: .outlined, diameter: 48) {
                    changeGoal(by: Self.goalStep)
                }
                .disabled(weeklyGoal >= Self.goalRange.upperBound)
            }
            // Holding a button keeps stepping, like the stepper it replaces.
            .buttonRepeatBehavior(.enabled)

            Hairline()

            VStack(alignment: .leading, spacing: 10) {
                WeekPlanStrip(weekdays: suggestion.weekdays)
                Text(suggestion.sentence(unit: unit))
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.inkMuted)
                    .contentTransition(.numericText())
            }
        }
        .raisedCard()
        .sensoryFeedback(trigger: weeklyGoal) { old, new in new > old ? .increase : .decrease }
    }

    private var goalValue: some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Int(weeklyGoal), format: .number)
                    .font(.metricLarge)
                    .monospacedDigit()
                    .tracking(-0.4)
                    .foregroundStyle(.ink)
                    .contentTransition(.numericText(value: weeklyGoal))
                Text(unit.distanceSymbol)
                    .font(.system(size: 20, weight: .bold).width(.expanded))
                    .foregroundStyle(.inkMuted)
            }
            Text("a week")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weekly goal")
        .accessibilityValue("\(Int(weeklyGoal)) \(unit == .metric ? "kilometers" : "miles") a week")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: changeGoal(by: Self.goalStep)
            case .decrement: changeGoal(by: -Self.goalStep)
            @unknown default: break
            }
        }
    }

    private func changeGoal(by step: Double) {
        let goal = min(max(weeklyGoal + step, Self.goalRange.lowerBound), Self.goalRange.upperBound)
        guard goal != weeklyGoal else { return }
        withAnimation(.snappy) { weeklyGoal = goal }
    }

    // MARK: Access

    private var access: some View {
        let offersHealth = HealthSync.shared.isAvailable
        return PageBody(bottomSpacing: Space.x5) { _ in
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: offersHealth ? "Two permissions" : "One permission",
                           message: offersHealth
                               ? "Both are optional, and you can change them later in Settings."
                               : "It's optional, and you can change it later in Settings.")
                    .padding(.top, 2)

                VStack(spacing: Space.x3) {
                    PermissionCard(symbol: "location", title: "Location",
                                   detail: "Maps your route and measures distance and pace.",
                                   noteSymbol: "lock", note: "Used only while you run",
                                   answer: locationAnswer) { location.request() }
                    if offersHealth {
                        PermissionCard(symbol: "heart", title: "Apple Health",
                                       detail: "Saves your runs, with route, to Health, and reads your weight and age for calories and zones.",
                                       noteSymbol: "clock",
                                       note: "Saves runs from today on. Add earlier ones anytime in Profile.",
                                       answer: healthAnswer, action: connectHealth)
                    }
                }
                .padding(.top, Space.x6)
            }
        }
    }

    private var locationAnswer: PermissionCard.Answer {
        switch location.status {
        case .notDetermined: .ask("Allow")
        case .authorizedWhenInUse, .authorizedAlways: .granted("Allowed")
        default: .off
        }
    }

    private var healthAnswer: PermissionCard.Answer {
        guard let healthConnected else { return .ask("Connect") }
        return healthConnected ? .granted("Connected") : .off
    }

    private func connectHealth() {
        healthSave = true
        // Runs from now on; earlier ones only when asked in Profile.
        UserDefaults.standard.set(Date.now, forKey: StrideSettings.healthSaveSince)
        Task {
            // Like Profile, saving stays on after a denial; Profile then explains how to allow it.
            let connected = await HealthSync.shared.requestAuthorization()
            withAnimation(.snappy) { healthConnected = connected }
        }
    }

    // MARK: Watch

    private var watch: some View {
        ArtPage(art: "watchRun", zoom: 1.07, shift: -22, heights: 150...250, idealHeight: 250,
                bottomSpacing: Space.x5) {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Better with\nApple Watch", message: "Start a run from your wrist, in a tap.")
                VStack(alignment: .leading, spacing: 14) {
                    FeatureRow(symbol: "heart", title: "Live heart rate and zones") {
                        ZoneScale(height: 20, showsNumbers: true)
                            .accessibilityHidden(true)
                    }
                    FeatureRow(symbol: "iphone", title: "Mirrored to this iPhone as it happens")
                    FeatureRow(symbol: "arrow.clockwise", title: "Leave your iPhone home. Runs sync later.")
                }
                .padding(.top, Space.x5)
            }
            .padding(.top, Space.x5)
        }
    }
}

// MARK: - Page layout

/// A page's scrolling body, at least as tall as the room between the top bar and the page dots,
/// so a page can keep a line at its foot. It scrolls when the text is large or the screen short.
private struct PageBody<Content: View>: View {
    /// The space kept above the page dots.
    let bottomSpacing: CGFloat
    @ViewBuilder let content: (_ viewportHeight: CGFloat) -> Content
    @State private var viewportHeight: CGFloat = 0

    var body: some View {
        ScrollView {
            content(viewportHeight)
                .padding(.horizontal, Space.x4)
                .padding(.bottom, bottomSpacing)
                .frame(maxWidth: .infinity, minHeight: viewportHeight, alignment: .topLeading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { viewportHeight = $0 }
    }
}

/// A page led by artwork in a 24pt rounded frame. The artwork takes the room the words leave,
/// within `heights`, so the page fits without scrolling on small screens and at larger text sizes
/// until the artwork reaches its smallest.
private struct ArtPage<Content: View>: View {
    let art: String
    /// How far past filling its frame the artwork is zoomed, and moved down, to crop it as designed.
    var zoom: CGFloat = 1
    var shift: CGFloat = 0
    let heights: ClosedRange<CGFloat>
    /// The designed height, used until the page is measured.
    let idealHeight: CGFloat
    let bottomSpacing: CGFloat
    @ViewBuilder var content: Content
    @State private var contentHeight: CGFloat = 0

    var body: some View {
        PageBody(bottomSpacing: bottomSpacing) { viewportHeight in
            VStack(alignment: .leading, spacing: 0) {
                Color.surfaceRaised
                    .overlay {
                        Illustration(name: art, contentMode: .fill)
                            .scaleEffect(zoom)
                            .offset(y: shift)
                    }
                    .frame(height: artHeight(in: viewportHeight))
                    .clipShape(RoundedRectangle(cornerRadius: Radius.lg))
                    .accessibilityHidden(true)
                    .padding(.top, Space.x2)
                content
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
        }
    }

    private func artHeight(in viewportHeight: CGFloat) -> CGFloat {
        guard viewportHeight > 0, contentHeight > 0 else { return idealHeight }
        let room = viewportHeight - Space.x2 - contentHeight - bottomSpacing
        return min(max(room, heights.lowerBound), heights.upperBound)
    }
}

/// A page's large title and what it's for.
private struct PageHeader: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(title)
                .font(.largeTitle.bold())
                .tracking(-0.3)
                .foregroundStyle(.ink)
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.body)
                .foregroundStyle(.inkMuted)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The small uppercase label over a control. VoiceOver hears the control's own label instead.
private struct LabeledField<Content: View>: View {
    let label: String
    let content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.x2) {
            Text(label)
                .metricLabelStyle()
                .accessibilityHidden(true)
            content
        }
    }
}

/// A line of what Stride does, after a symbol in a small raised circle, with room for a picture of
/// it under the words.
private struct FeatureRow<Extra: View>: View {
    let symbol: String
    let title: String
    @ViewBuilder var extra: Extra

    var body: some View {
        HStack(alignment: .top, spacing: Space.x3) {
            IconBadge(symbol, style: .raised, size: 32)
            VStack(alignment: .leading, spacing: Space.x2) {
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.ink)
                    .fixedSize(horizontal: false, vertical: true)
                extra
            }
            // Centers a single line on the 32pt circle.
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }
}

extension FeatureRow where Extra == EmptyView {
    init(symbol: String, title: String) {
        self.init(symbol: symbol, title: title) { EmptyView() }
    }
}

/// The Stride mark, a tilted track oval, and the wordmark.
private struct BrandLockup: View {
    var body: some View {
        HStack(spacing: Space.x2) {
            Ellipse()
                .stroke(Color.track, lineWidth: 2.6)
                .frame(width: 22, height: 13)
                .rotationEffect(.degrees(-12))
                .frame(width: 26, height: 18)
            Text(verbatim: "Stride")
                .font(.system(size: 20, weight: .heavy).width(.expanded))
                .tracking(-0.2)
                .foregroundStyle(.ink)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "Stride"))
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Permissions

/// A permission to ask for: what it's for and a note on how it's used, with a button that becomes
/// its answer.
private struct PermissionCard: View {
    enum Answer: Equatable {
        case ask(String)
        case granted(String)
        case off
    }

    let symbol: String
    let title: String
    let detail: String
    let noteSymbol: String
    let note: String
    let answer: Answer
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Space.x3) {
            IconBadge(symbol, style: .brand, size: 40)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: Space.x2) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.ink)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Space.x2)
                    answerView
                }
                .frame(minHeight: Dimension.hitMin)
                .animation(.snappy, value: answer)

                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: noteSymbol)
                        .accessibilityHidden(true)
                    Text(note)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(.inkMuted)
                .padding(.top, Space.x1)
            }
        }
        .raisedCard()
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder private var answerView: some View {
        switch answer {
        case .ask(let label):
            Button(label, action: action)
                .buttonStyle(OutlinedCapsuleButtonStyle())
                .accessibilityLabel("\(label) \(title)")
                .transition(.opacity)
        case .granted(let label):
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .bold))
                    .accessibilityHidden(true)
                Text(label)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.success)
            .frame(minHeight: Dimension.hitMin)
            .accessibilityElement(children: .combine)
            .transition(.opacity)
        case .off:
            Text("Off")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.inkMuted)
                .frame(minHeight: Dimension.hitMin)
                .transition(.opacity)
        }
    }
}

/// A 44pt capsule outlined in `lineStrong`, sized to its label: Allow, Connect.
private struct OutlinedCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.ink)
            .lineLimit(1)
            .padding(.horizontal, 20)
            .frame(minHeight: Dimension.hitMin)
            .background(Capsule().strokeBorder(Color.lineStrong, lineWidth: 1.5))
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Dots under the pages, the current one in the brand color.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: Space.x2) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? Color.track : Color.line)
                    .frame(width: index == current ? 20 : 8, height: 8)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel("Page \(current + 1) of \(count)")
    }
}

private extension View {
    /// The designed leading for display type, from iOS 26; earlier systems keep the font's own.
    @ViewBuilder
    func exactLineHeight(_ points: CGFloat) -> some View {
        if #available(iOS 26.0, *) {
            lineHeight(.exact(points: points))
        } else {
            self
        }
    }
}

/// Asks for location while the app is in use, and follows the answer.
@Observable
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private(set) var status: CLAuthorizationStatus
    @ObservationIgnored private let manager: CLLocationManager

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        status = manager.authorizationStatus
        super.init()
        manager.delegate = self
    }

    func request() {
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in self.status = status }
    }
}

#Preview {
    OnboardingView {}
}
