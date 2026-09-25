import SwiftUI
import SwiftData
import StrideKit
import StrideUI

enum AppTab: Hashable {
    case home, activities, run, progress, profile
}

struct RootView: View {
    @Environment(RunTracker.self) private var tracker
    @Environment(MirroredWorkout.self) private var mirrored
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
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard arguments.contains("-demoMirroredWorkout") else { return }
            mirrored.startDemo()
            if arguments.contains("-demoDisconnect") {
                try? await Task.sleep(for: .seconds(5))
                mirrored.simulateDisconnect()
            }
        }
        #endif
        // A Watch run shows live here unless an iPhone run is already on screen.
        .background {
            Color.clear
                .fullScreenCover(isPresented: Binding(get: { mirrored.isPresented && !tracker.isPresented }, set: { _ in }),
                                 onDismiss: { if mirrored.isDismissing { mirrored.reset() } }) {
                    MirroredRunView()
                        .environment(mirrored)
                        .interactiveDismissDisabled()
                }
        }
        .task { tracker.restoreIfNeeded() }
        .task { await RunMaintenance.backfillBestEfforts(in: context) }
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
    /// Launch with `-seedSampleData` to replace all data with the example runs, and with
    /// `-exportShareCard` to write the newest GPS run's share card to Documents/share-card.png.
    private func seedSampleDataIfRequested() async {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-seedSampleData") {
            try? context.delete(model: Run.self)
            try? context.delete(model: Shoe.self)
            try? context.delete(model: Challenge.self)
            await SampleData.insert(into: context)
            ShoeDefaults.set(try? context.fetch(FetchDescriptor<Shoe>(predicate: #Predicate { $0.name == "Daily Trainer" })).first)
        }
        if arguments.contains("-exportShareCard") {
            let runs = (try? context.fetch(FetchDescriptor<Run>(sortBy: [SortDescriptor(\.startDate, order: .reverse)]))) ?? []
            guard let run = runs.first(where: { !$0.isManual }) else { return }
            let card = ShareCardView(title: run.title, date: run.startDate, distance: run.distance, duration: run.duration,
                                     elevationGain: run.elevationGain, coordinates: run.preview, unit: .metric)
            try? card.uiImage()?.pngData()?.write(to: URL.documentsDirectory.appending(path: "share-card.png"))
        }
    }
    #endif
}
