import WidgetKit
import SwiftUI

@main
struct QueueWidgetsBundle: WidgetBundle {
    var body: some Widget {
        FocusTimerWidget()
        FocusTimerLockScreenWidget()
        #if canImport(ActivityKit)
        if #available(iOS 18.0, *) {
            FocusLiveActivityWidget()
        } else {
            FocusLiveActivityFallbackWidget()
        }
        #endif
    }
}
