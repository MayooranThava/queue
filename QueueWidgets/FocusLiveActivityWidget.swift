import SwiftUI
import QueueCore
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit)
import ActivityKit

struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FocusActivityAttributes.self) { context in
            lockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Focus", systemImage: "leaf.fill")
                        .font(.caption)
                        .foregroundStyle(QueueWidgetColors.sage)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    liveClock(context.state, fontSize: 18)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.taskTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(statusCaption(context.state))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(QueueWidgetColors.sage)
            } compactTrailing: {
                liveClock(context.state, fontSize: 14)
                    .minimumScaleFactor(0.6)
            } minimal: {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(QueueWidgetColors.sage)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        let snapshot = FocusWidgetSnapshot(
            taskID: context.attributes.taskID,
            taskTitle: context.state.taskTitle,
            difficultyDisplayName: context.state.difficultyDisplayName,
            estimatedDuration: context.state.estimatedDuration,
            session: context.state.session
        )
        let progress = context.state.progress()
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.taskTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(QueueWidgetColors.ivory)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                Text(statusCaption(context.state))
                    .font(.caption)
                    .foregroundStyle(QueueWidgetColors.ivory.opacity(0.55))
                    .lineLimit(1)
                LiveCountdownText(snapshot: snapshot, at: Date(), fontSize: 30)
            }
            Spacer(minLength: 0)
            WidgetCompanionBadge(
                state: {
                    switch context.state.session.state {
                    case .paused: return .paused
                    case .expired: return .expired
                    default: return .working
                    }
                }(),
                progress: progress
            )
        }
        .padding(16)
        .activityBackgroundTint(QueueWidgetColors.charcoal)
        .activitySystemActionForegroundColor(QueueWidgetColors.ivory)
        .widgetURL(QueueDeepLink.focus)
    }

    @ViewBuilder
    private func liveClock(_ state: FocusActivityAttributes.ContentState, fontSize: CGFloat) -> some View {
        let now = Date()
        if state.session.state == .running, let end = state.session.runningEndDate(at: now) {
            Text(timerInterval: now...end, countsDown: true)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
        } else {
            Text(FocusTimerFormatting.clock(state.remaining(at: now)))
                .font(.system(size: fontSize, weight: .semibold, design: .rounded).monospacedDigit())
                .lineLimit(1)
        }
    }

    private func statusCaption(_ state: FocusActivityAttributes.ContentState) -> String {
        switch state.session.state {
        case .paused: return "Paused · \(state.difficultyDisplayName)"
        case .expired: return "Time’s up — finish when you’re ready"
        default: return "\(state.difficultyDisplayName) · focusing"
        }
    }
}
#endif
