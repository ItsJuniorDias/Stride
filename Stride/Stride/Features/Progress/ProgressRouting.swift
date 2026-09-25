import SwiftUI
import StrideKit
import StrideUI

/// Screens reachable from Progress and Profile.
enum ProgressRoute: Hashable {
    case records, challenges, shoes, friends
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
            }
        }
        .navigationDestination(for: Shoe.self) { ShoeDetailView(shoe: $0) }
        .navigationDestination(for: Challenge.self) { ChallengeDetailView(challenge: $0) }
    }
}

/// A section title with an optional "See all" link.
struct SectionHeader: View {
    let title: String
    var route: ProgressRoute?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.headline).foregroundStyle(.ink)
            Spacer()
            if let route {
                NavigationLink("See all", value: route)
                    .font(.subheadline.weight(.semibold))
            }
        }
        .accessibilityElement(children: .contain)
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
