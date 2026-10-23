import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Reloads both Queue widget kinds after a snapshot write or a focus action.
enum QueueWidgetReload {
    static let homeKind = "FocusTimerWidget"
    static let lockScreenKind = "FocusTimerLockScreenWidget"

    static func reload() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: homeKind)
        WidgetCenter.shared.reloadTimelines(ofKind: lockScreenKind)
        #endif
    }
}
