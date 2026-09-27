import SwiftUI
import StrideKit
import StrideUI

/// Screens reachable from Progress and Profile.
enum ProgressRoute: Hashable {
    case records, challenges, shoes, friends
    /// All five training paces, from the race predictions card.
    case trainingPaces
}

extension View {
    /// Registers where progress routes, shoes and challenges lead. Runs are registered by each stack.
    func progressDestinations() -> some View {
        navigationDestination(for: ProgressRoute.self) { route in
            switch route {
            case .records: RecordsView()
            case .challenges: ChallengesView()
            case .shoes: ShoesView()
            case .friends: FriendsView()
            case .trainingPaces: TrainingPacesView()
            }
        }
        .navigationDestination(for: Shoe.self) { ShoeDetailView(shoe: $0) }
        .navigationDestination(for: Challenge.self) { ChallengeDetailView(challenge: $0) }
    }
}

/// A section title with an optional "See all" link, in the style of ``SectionHeading``.
struct SectionHeader: View {
    let title: String
    var route: ProgressRoute?

    var body: some View {
        SectionHeading(title) {
            if let route {
                NavigationLink(value: route) { LinkLabel("See all") }
                    .buttonStyle(.strideLink)
                    .padding(.vertical, -11)
            }
        }
        .accessibilityElement(children: .contain)
    }
}

/// "See all" in a card heading, kept to the heading's height so the tap target doesn't push the card open.
struct SeeAllLink: View {
    let route: ProgressRoute
    var title = "See all"

    var body: some View {
        NavigationLink(value: route) { LinkLabel(title) }
            .buttonStyle(.strideLink)
            .padding(.vertical, -11)
    }
}

/// "Sep 20", with the year when it isn't this year ("Sep 20, 2025").
func shortDate(_ date: Date, alwaysYear: Bool = false) -> String {
    let thisYear = Calendar.current.isDate(date, equalTo: .now, toGranularity: .year)
    return date.formatted(thisYear && !alwaysYear ? .dateTime.month(.abbreviated).day() : .dateTime.month(.abbreviated).day().year())
}

/// "142h 05m" style totals: clock time reads badly past a day.
func totalTime(_ seconds: TimeInterval) -> String {
    guard seconds >= 3_600 else { return RunFormat.duration(seconds) }
    let minutes = Int(seconds / 60)
    return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m"
}
