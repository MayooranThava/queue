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
                    Text(FocusTimerFormatting.clock(context.state.remaining()))
                        .font(.system(size: 18, weight: .semibold, design: .rounded).monospacedDigit())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.taskTitle)
                        .font(.headline)
                        .lineLimit(1)
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
                Text(FocusTimerFormatting.clock(context.state.remaining()))
                    .font(.system(size: 14, weight: .semibold, design: .rounded).monospacedDigit())
                    .minimumScaleFactor(0.7)
            } minimal: {
                Image(systemName: "leaf.fill")
                    .foregroundStyle(QueueWidgetColors.sage)
            }
        }
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<FocusActivityAttributes>) -> some View {
        let remaining = context.state.remaining()
        let progress = context.state.progress()
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(context.state.taskTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(QueueWidgetColors.ivory)
                    .lineLimit(2)
                Text(statusCaption(context.state))
                    .font(.caption)
                    .foregroundStyle(QueueWidgetColors.ivory.opacity(0.55))
                Text(FocusTimerFormatting.clock(remaining))
                    .font(.system(size: 32, weight: .medium, design: .rounded).monospacedDigit())
                    .foregroundStyle(QueueWidgetColors.ivory)
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
