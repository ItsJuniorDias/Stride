import SwiftUI
import StrideUI

struct ProgressDashboardView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Nothing to chart yet",
                systemImage: "chart.bar.fill",
                description: Text("Weekly totals, records and streaks appear after your first run.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surface)
            .navigationTitle("Progress")
        }
    }
}

#Preview {
    ProgressDashboardView()
}
