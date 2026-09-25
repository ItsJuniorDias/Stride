import SwiftUI
import WatchKit
import StrideUI

/// Workout pages, following watchOS conventions: controls on the left, metrics in the middle,
/// heart-rate zones next, Now Playing on the right.
struct SessionPagingView: View {
    @Environment(WorkoutManager.self) private var workout
    @State private var page: Page = .metrics

    enum Page: Hashable { case controls, metrics, zones, nowPlaying }

    var body: some View {
        TabView(selection: $page) {
            WatchControlsView().tag(Page.controls)
            WatchMetricsView().tag(Page.metrics)
            WatchZonesView().tag(Page.zones)
            NowPlayingView().tag(Page.nowPlaying)
        }
        .tabViewStyle(.page(indexDisplayMode: .automatic))
        .navigationBarBackButtonHidden(true)
        // Pausing shows the controls; resuming returns to the numbers.
        .onChange(of: workout.phase) { _, phase in
            withAnimation { page = phase == .paused ? .controls : .metrics }
        }
    }
}
