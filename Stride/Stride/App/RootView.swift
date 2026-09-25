import SwiftUI
import StrideUI

enum AppTab: Hashable {
    case home, activities, run, progress, profile
}

struct RootView: View {
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house.fill", value: .home) {
                HomeView(selectedTab: $selectedTab)
            }
            Tab("Activities", systemImage: "list.bullet", value: .activities) {
                ActivitiesView()
            }
            Tab("Run", systemImage: "figure.run", value: .run) {
                RunSetupView()
            }
            Tab("Progress", systemImage: "chart.bar.fill", value: .progress) {
                ProgressDashboardView()
            }
            Tab("Profile", systemImage: "person.fill", value: .profile) {
                ProfileView()
            }
        }
        .tint(.track)
    }
}

#Preview {
    RootView()
}
