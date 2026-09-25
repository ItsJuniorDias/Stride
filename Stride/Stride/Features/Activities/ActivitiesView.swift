import SwiftUI
import StrideUI

struct ActivitiesView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "No runs yet",
                systemImage: "figure.run",
                description: Text("Your runs will show up here after you finish one.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.surface)
            .navigationTitle("Activities")
        }
    }
}

#Preview {
    ActivitiesView()
}
