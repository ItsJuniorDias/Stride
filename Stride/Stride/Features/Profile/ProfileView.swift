import SwiftUI
import StrideUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            List {
                #if DEBUG
                Section("Developer") {
                    NavigationLink("Design System") { DesignSystemGallery() }
                }
                #endif
            }
            .scrollContentBackground(.hidden)
            .background(Color.surface)
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ProfileView()
}
