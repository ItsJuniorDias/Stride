import SwiftUI
import SwiftData
import StrideKit
import StrideUI

enum AppTab: Hashable {
    case home, activities, run, progress, profile
}

struct RootView: View {
    @Environment(RunTracker.self) private var tracker
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
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
        #if DEBUG
        .task { await seedSampleDataIfRequested() }
        #endif
        .task { tracker.restoreIfNeeded() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { tracker.checkpoint() }
        }
        .fullScreenCover(isPresented: Binding(get: { tracker.isPresented }, set: { _ in }), onDismiss: deleteDiscardedRun) {
            LiveRunView()
                .environment(tracker)
                .environment(\.modelContext, context)
                .interactiveDismissDisabled()
        }
    }

    /// Deletes a run discarded from the summary, after the cover has animated away.
    private func deleteDiscardedRun() {
        if tracker.isDismissing { tracker.reset() }
        guard let run = tracker.takeRunPendingDeletion() else { return }
        context.delete(run)
        try? context.save()
    }

    #if DEBUG
    /// Launch with `-seedSampleData` to replace all data with the example runs.
    private func seedSampleDataIfRequested() async {
        guard ProcessInfo.processInfo.arguments.contains("-seedSampleData") else { return }
        try? context.delete(model: Run.self)
        try? context.delete(model: Shoe.self)
        await SampleData.insert(into: context)
    }
    #endif
}
