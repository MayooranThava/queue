import WidgetKit
import SwiftUI

@main
struct QueueWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FocusTimerWidget()
        FocusTimerLockScreenWidget()
        #if canImport(ActivityKit)
        FocusLiveActivityWidget()
        #endif
    }
}
