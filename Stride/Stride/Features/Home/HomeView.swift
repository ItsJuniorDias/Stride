import SwiftUI
import StrideUI

struct HomeView: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.x5) {
                    weeklyGoal
                    Button("Start a run") { selectedTab = .run }
                        .buttonStyle(.stridePrimary)
                }
                .padding(Space.x4)
            }
            .background(Color.surface)
            .navigationTitle(greeting)
        }
    }

    private var weeklyGoal: some View {
        HStack(spacing: Space.x5) {
            ProgressRing(progress: 0) {
                VStack(spacing: 2) {
                    Text("0.0").font(.metricSmall).monospacedDigit().foregroundStyle(.ink)
                    Text("of 20 km").metricLabelStyle()
                }
            }
            .frame(width: 120, height: 120)
            VStack(alignment: .leading, spacing: Space.x1) {
                Text("This week").font(.headline).foregroundStyle(.ink)
                Text("No runs yet").font(.subheadline).foregroundStyle(.inkMuted)
                Text("20 km to go").font(.subheadline).foregroundStyle(.inkMuted)
            }
            Spacer(minLength: 0)
        }
        .padding(Space.x4)
        .background(Color.surfaceRaised, in: RoundedRectangle(cornerRadius: Radius.md))
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }
}

#Preview {
    HomeView(selectedTab: .constant(.home))
}
