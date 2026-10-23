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
            estimatedDuration: snapshot.estimatedDuration,
            showsCompanion: CompanionPreferenceStore.isVisible(),
            nextTaskTitle: QueueActivityStore.load()?.nextQueuedTitle
        )
        let attributes = FocusActivityAttributes(taskID: snapshot.taskID)
        // Re-render at the end so Time's up can replace the running countdown without a push.
        let staleDate = snapshot.session.state == .running ? snapshot.runningEndDate() : nil
        let content = ActivityContent(state: state, staleDate: staleDate)

        if let existing = Activity<FocusActivityAttributes>.activities.first(where: {
            $0.attributes.taskID == snapshot.taskID
        }) {
            await existing.update(content)
            return
        }

        for stale in Activity<FocusActivityAttributes>.activities {
            await stale.end(nil, dismissalPolicy: .immediate)
        }

        _ = try? Activity.request(attributes: attributes, content: content, pushType: nil)
        #endif
    }
}
