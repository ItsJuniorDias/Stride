import WidgetKit
import SwiftUI

@main
struct StrideWidgetsBundle: WidgetBundle {
    var body: some Widget {
        WeeklyWidget()
        FriendsWidget()
        QuickStartWidget()
        StartRunControl()
        RunLiveActivityWidget()
    }
}
