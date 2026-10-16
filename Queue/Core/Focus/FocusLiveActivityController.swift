import Foundation
import QueueCore
#if canImport(ActivityKit)
import ActivityKit
#endif

/// Starts / updates / ends the Lock Screen + Dynamic Island Live Activity from focus timestamps.
@MainActor
enum FocusLiveActivityController {
    static let shared = FocusLiveActivityControllerBox()
}

@MainActor
final class FocusLiveActivityControllerBox {
    func sync(snapshot: FocusWidgetSnapshot?) async {
        #if canImport(ActivityKit)
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        guard let snapshot, snapshot.isActivelyTiming else {
            for activity in Activity<FocusActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }

        let state = FocusActivityAttributes.ContentState(
            session: snapshot.session,
            taskTitle: snapshot.taskTitle,
            difficultyDisplayName: snapshot.difficultyDisplayName,
            estimatedDuration: snapshot.estimatedDuration
        )
        let attributes = FocusActivityAttributes(taskID: snapshot.taskID)

        if let existing = Activity<FocusActivityAttributes>.activities.first(where: {
            $0.attributes.taskID == snapshot.taskID
        }) {
            await existing.update(ActivityContent(state: state, staleDate: nil))
            return
        }

        for stale in Activity<FocusActivityAttributes>.activities {
            await stale.end(nil, dismissalPolicy: .immediate)
        }

        let content = ActivityContent(state: state, staleDate: nil)
        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        #endif
    }
}
