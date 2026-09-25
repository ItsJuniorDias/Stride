import SwiftUI
import CoreLocation
import StrideKit
import StrideUI

/// The first launch on a device: what Stride is, the runner's name, unit and weekly goal, location
/// and Apple Health, and Apple Watch. Everything can be changed later in Profile.
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
    @State private var healthAsked = false
    @FocusState private var nameFocused: Bool

    enum Page: Int, CaseIterable {
        case welcome, you, access, watch
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if page != .welcome {
                    Button("Back", systemImage: "chevron.left", action: back)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.lane)
                }
                Spacer()
            }
            .frame(minHeight: Dimension.hitMin)
            .padding(.horizontal, Space.x4)

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

            VStack(spacing: Space.x4) {
                PageDots(count: Page.allCases.count, current: page.rawValue)
                Button(page == .watch ? "Start running" : page == .welcome ? "Get started" : "Continue", action: next)
                    .buttonStyle(.stridePrimary)
            }
            .padding(.horizontal, Space.x4)
            .padding(.bottom, Space.x4)
        }
        .background(Color.surface)
        .sensoryFeedback(.selection, trigger: page)
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

    // MARK: Pages

    private var welcome: some View {
        OnboardingPage(illustration: "onboardingWelcome", imageHeight: 320,
                       title: "Every run, recorded and coached",
                       message: "Track your runs with GPS on iPhone or Apple Watch, follow a plan with a coach in your ear, and watch your weeks add up.") {
            EmptyView()
        }
    }

    private var you: some View {
        OnboardingPage(illustration: nil, title: "A little about you",
                       message: "So Stride greets you by name and measures the way you do.") {
            VStack(alignment: .leading, spacing: Space.x4) {
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text("Name").metricLabelStyle()
                    TextField("Your name", text: $userName)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .padding(.horizontal, Space.x4)
                        .frame(minHeight: Dimension.hitMin)
                        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                }
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text("Units").metricLabelStyle()
                    Picker("Units", selection: $unit) {
                        Text("Kilometers").tag(UnitSystem.metric)
                        Text("Miles").tag(UnitSystem.imperial)
                    }
                    .pickerStyle(.segmented)
                }
                VStack(alignment: .leading, spacing: Space.x2) {
                    Text("Weekly goal").metricLabelStyle()
                    Stepper(value: $weeklyGoal, in: 5...300, step: 5) {
                        Text("\(Int(weeklyGoal)) \(unit.distanceSymbol) a week")
                            .font(.headline)
                            .foregroundStyle(.ink)
                    }
                    .padding(.horizontal, Space.x4)
                    .frame(minHeight: Dimension.hitMin)
                    .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
                }
            }
        }
    }

    private var access: some View {
        OnboardingPage(illustration: nil, title: "Two permissions",
                       message: "Both are optional, and you can change them later in Settings.") {
            VStack(spacing: Space.x3) {
                PermissionRow(symbol: "location.fill", title: "Location",
                              detail: "Maps your route and measures distance and pace. Used only while you run.",
                              state: locationState, action: location.request)
                if HealthSync.shared.isAvailable {
                    PermissionRow(symbol: "heart.fill", title: "Apple Health",
                                  detail: "Saves your runs, with route, to Health and reads your weight and age for calories and zones.",
                                  state: healthState, action: connectHealth)
                }
            }
        }
    }

    private var watch: some View {
        OnboardingPage(illustration: "watchRun", imageHeight: 260, title: "Better with Apple Watch",
                       message: "Start a run on your wrist with live heart rate and zones. It shows here as it happens, and your iPhone can stay home.") {
            EmptyView()
        }
    }

    // MARK: Permissions

    private var locationState: PermissionRow.State {
        switch location.status {
        case .notDetermined: .ask("Allow")
        case .authorizedWhenInUse, .authorizedAlways: .done("Allowed")
        default: .done("Off")
        }
    }

    private var healthState: PermissionRow.State {
        healthAsked || healthSave ? .done("Connected") : .ask("Connect")
    }

    private func connectHealth() {
        healthSave = true
        // Runs from now on; earlier ones only when asked in Profile.
        UserDefaults.standard.set(Date.now, forKey: StrideSettings.healthSaveSince)
        Task {
            _ = await HealthSync.shared.requestAuthorization()
            healthAsked = true
        }
    }
}

/// One onboarding page: optional artwork, a title and a message, then the page's own controls.
private struct OnboardingPage<Content: View>: View {
    let illustration: String?
    var imageHeight: CGFloat = 280
    let title: String
    let message: String
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.x4) {
                if let illustration {
                    Illustration(name: illustration, contentMode: .fill)
                        .frame(height: imageHeight)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
                        .padding(.bottom, Space.x2)
                } else {
                    Spacer().frame(height: Space.x6)
                }
                Text(title).font(.largeTitle.bold()).foregroundStyle(.ink)
                Text(message).font(.body).foregroundStyle(.inkMuted)
                content
                    .padding(.top, Space.x2)
            }
            .padding(Space.x4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

/// A permission to ask for: what it's for, and a button that becomes its answer.
private struct PermissionRow: View {
    enum State {
        case ask(String)
        case done(String)
    }

    let symbol: String
    let title: String
    let detail: String
    let state: State
    let action: () -> Void

    var body: some View {
        HStack(spacing: Space.x3) {
            ProSymbol(symbol)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
                Text(detail).font(.caption).foregroundStyle(.inkMuted)
            }
            Spacer(minLength: Space.x2)
            switch state {
            case .ask(let label):
                Button(label, action: action)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.lane)
            case .done(let label):
                Text(label).font(.subheadline).foregroundStyle(.inkMuted)
            }
        }
        .raisedCard()
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
