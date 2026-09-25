import WidgetKit
import SwiftUI

@main
struct StrideWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WeeklyWidget()
        QuickStartWidget()
        StartRunControl()
        RunLiveActivityWidget()
    }
}
