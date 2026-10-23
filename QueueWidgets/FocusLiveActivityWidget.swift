import SwiftUI
import QueueCore
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(ActivityKit)
import ActivityKit
import AppIntents
import UIKit

/// Lock Screen Live Activity, plus the watchOS 11 Smart Stack size on iOS 18+.
@available(iOS 18.0, *)
struct FocusLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        FocusLiveActivityFamilies.includingWatch(makeFocusLiveActivityConfiguration())
    }
}

@available(iOS 18.0, *)
private enum FocusLiveActivityFamilies {
    static func includingWatch<Configuration: WidgetConfiguration>(
        _ configuration: Configuration
    ) -> some WidgetConfiguration {
        configuration.supplementalActivityFamilies([.small])
    }
}

/// Same activity for iOS 17, which has no supplemental activity families.
struct FocusLiveActivityFallbackWidget: Widget {
    var body: some WidgetConfiguration {
        makeFocusLiveActivityConfiguration()
    }
}

private func makeFocusLiveActivityConfiguration() -> some WidgetConfiguration {
    ActivityConfiguration(for: FocusActivityAttributes.self) { context in
        FocusLiveActivityLockScreen(context: context)
    } dynamicIsland: { context in
        let timeUp = focusIsTimeUp(context)
        DynamicIsland {
            DynamicIslandExpandedRegion(.leading) {
                LiveActivityCompanionRing(state: context.state, isComplete: timeUp, diameter: 44)
            }
            DynamicIslandExpandedRegion(.trailing) {
                LiveCountdownText(
                    snapshot: context.state.focusSnapshot(),
                    at: Date(),
                    fontSize: 17,
                    weight: .semibold,
                    minimumScale: 0.6
                )
            }
            DynamicIslandExpandedRegion(.center) {
                Text(context.state.taskTitle)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(QueueColors.dark(.textPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            DynamicIslandExpandedRegion(.bottom) {
                FocusLiveActivityExpandedDetails(context: context)
            }
        } compactLeading: {
            LiveActivityCompanionRing(state: context.state, isComplete: timeUp, diameter: 24)
        } compactTrailing: {
            LiveCountdownText(
                snapshot: context.state.focusSnapshot(),
                at: Date(),
                fontSize: 14,
                weight: .semibold,
                minimumScale: 0.55
            )
        } minimal: {
            LiveActivityCompanionRing(state: context.state, isComplete: timeUp, diameter: 22)
        }
    }
}

private struct FocusLiveActivityLockScreen: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                FocusLiveActivityFamilySwitch(context: context)
            } else {
                FocusLiveActivityPhoneLayout(context: context)
            }
        }
        .environment(\.colorScheme, .dark)
        .activityBackgroundTint(QueueColors.dark(.background))
        .activitySystemActionForegroundColor(QueueColors.dark(.textPrimary))
        .widgetURL(QueueDeepLink.focus)
    }
}

@available(iOS 18.0, *)
private struct FocusLiveActivityFamilySwitch: View {
    @Environment(\.activityFamily) private var activityFamily
    let context: ActivityViewContext<FocusActivityAttributes>

    var body: some View {
        switch activityFamily {
        case .small:
            FocusLiveActivityWatchLayout(context: context)
        default:
            FocusLiveActivityPhoneLayout(context: context)
        }
    }
}

/// Lock Screen card. Padding follows the app cards (16pt inset, 12pt corners).
private struct FocusLiveActivityPhoneLayout: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    private var timeUp: Bool { focusIsTimeUp(context) }
    private var paused: Bool { context.state.session.state == .paused }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.taskTitle)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(QueueColors.dark(.textPrimary))
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Text(caption)
                        .font(.system(size: 13, weight: timeUp || paused ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                    LiveCountdownText(
                        snapshot: context.state.focusSnapshot(),
                        at: Date(),
                        fontSize: 32,
                        weight: .semibold
                    )
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 8)
                LiveActivityCompanionRing(state: context.state, isComplete: timeUp, diameter: 56)
            }
            if let line = FocusActivityChrome.nextLine(context.state.nextTaskTitle) {
                Text(line)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(QueueColors.dark(.textSecondary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            LiveActivityActionRow(buttons: focusButtons(context))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }

    private var caption: String {
        FocusActivityChrome.statusCaption(
            state: context.state.session.state,
            difficultyDisplayName: context.state.difficultyDisplayName,
            remaining: context.state.remaining(),
            isStale: context.isStale
        )
    }

    private var statusColor: Color {
        if timeUp { return QueueColors.dark(.accent) }
        if paused { return QueueColors.dark(.textPrimary) }
        return QueueColors.dark(.textSecondary)
    }
}

/// watchOS 11 Smart Stack. Forest background comes from the shared activity tint.
private struct FocusLiveActivityWatchLayout: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    private var timeUp: Bool { focusIsTimeUp(context) }
    private var paused: Bool { context.state.session.state == .paused }

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.taskTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(QueueColors.dark(.textPrimary))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if timeUp || paused {
                    Text(caption)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(timeUp ? QueueColors.dark(.accent) : QueueColors.dark(.textPrimary))
                        .lineLimit(1)
                }
                LiveCountdownText(
                    snapshot: context.state.focusSnapshot(),
                    at: Date(),
                    fontSize: 16,
                    weight: .semibold,
                    minimumScale: 0.6
                )
                LiveActivityDoneButton()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            LiveActivityCompanionRing(state: context.state, isComplete: timeUp, diameter: 32)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .dynamicTypeSize(.xSmall ... .large)
    }

    private var caption: String {
        FocusActivityChrome.statusCaption(
            state: context.state.session.state,
            difficultyDisplayName: context.state.difficultyDisplayName,
            remaining: context.state.remaining(),
            isStale: context.isStale
        )
    }
}

private struct FocusLiveActivityExpandedDetails: View {
    let context: ActivityViewContext<FocusActivityAttributes>

    private var timeUp: Bool { focusIsTimeUp(context) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(caption)
                    .font(.system(size: 12, weight: timeUp || context.state.session.state == .paused ? .semibold : .medium, design: .rounded))
                    .foregroundStyle(timeUp ? QueueColors.dark(.accent) : QueueColors.dark(.textSecondary))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let line = FocusActivityChrome.nextLine(context.state.nextTaskTitle) {
                    Text(line)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(QueueColors.dark(.textSecondary))
                        .lineLimit(1)
                }
            }
            LiveActivityActionRow(buttons: focusButtons(context))
        }
        .widgetURL(QueueDeepLink.focus)
    }

    private var caption: String {
        FocusActivityChrome.statusCaption(
            state: context.state.session.state,
            difficultyDisplayName: context.state.difficultyDisplayName,
            remaining: context.state.remaining(),
            isStale: context.isStale
        )
    }
}

private struct LiveActivityCompanionRing: View {
    let state: FocusActivityAttributes.ContentState
    var isComplete: Bool
    var diameter: CGFloat

    @Environment(\.colorScheme) private var colorScheme

    private var lineWidth: CGFloat { max(2.5, diameter * 0.08) }

    /// Terracotta while running or in light mode. Honey only finishes a dark ring.
    private var ringColor: Color {
        FocusActivityChrome.ringUsesHoney(isComplete: isComplete, isDark: colorScheme == .dark)
            ? QueueColors.accent
            : QueueColors.primary
    }

    var body: some View {
        ZStack {
            ring
            center
                .padding(diameter * 0.16)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var ring: some View {
        if let interval = runningInterval {
            ProgressView(timerInterval: interval, countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .progressViewStyle(.circular)
            .tint(ringColor)
            .labelsHidden()
            .frame(width: diameter, height: diameter)
        } else {
            let fraction = CGFloat(isComplete ? 1 : min(1, max(0, state.progress())))
            ZStack {
                Circle()
                    .stroke(QueueColors.dark(.textPrimary).opacity(0.18), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: fraction)
                    .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
    }

    /// Full planned window, so the system ring keeps matching the countdown without activity updates.
    private var runningInterval: ClosedRange<Date>? {
        guard !isComplete, state.session.state == .running else { return nil }
        let now = Date()
        guard state.remaining(at: now) > 0, let end = state.session.runningEndDate(at: now) else { return nil }
        let start = end.addingTimeInterval(-max(1, state.session.totalPlanned))
        guard start < end else { return nil }
        return start...end
    }

    @ViewBuilder
    private var center: some View {
        if state.showsCompanion, let image = LiveActivityCompanionArt.image(for: pose) {
            Image(uiImage: image)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "leaf.fill")
                .font(.system(size: max(9, diameter * 0.34), weight: .semibold))
                .foregroundStyle(isComplete ? ringColor : QueueColors.success)
        }
    }

    private var pose: LiveActivityCompanionPose {
        if isComplete { return .done }
        if state.session.state == .paused { return .idle }
        return .working
    }

    private var accessibilityLabel: String {
        if !state.showsCompanion {
            return isComplete ? "Time\u{2019}s up" : "Focus"
        }
        if isComplete { return "Companion finished" }
        if state.session.state == .paused { return "Companion paused" }
        return "Companion focusing"
    }
}

/// Small companion frames that live in this extension. The 768px stills are too
/// large for a Live Activity, and the system replaces them with a grey box.
private enum LiveActivityCompanionPose {
    case idle
    case working
    case done

    var assetName: String {
        switch self {
        case .idle: return "LiveCompanionIdle"
        case .working: return "LiveCompanionWorking"
        case .done: return "LiveCompanionDone"
        }
    }
}

private enum LiveActivityCompanionArt {
    static let maxPixelLength: CGFloat = 96

    static func image(for pose: LiveActivityCompanionPose) -> UIImage? {
        guard let image = UIImage(named: pose.assetName, in: .main, compatibleWith: nil) else {
            return nil
        }
        let pixelsWide = image.size.width * image.scale
        let pixelsHigh = image.size.height * image.scale
        guard pixelsWide >= 8, pixelsHigh >= 8 else { return nil }
        guard pixelsWide <= maxPixelLength, pixelsHigh <= maxPixelLength else { return nil }
        return image
    }
}

private struct LiveActivityActionRow: View {
    let buttons: [QueueWidgetButton]

    var body: some View {
        if !buttons.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { _, button in
                    control(button)
                }
            }
        }
    }

    @ViewBuilder
    private func control(_ button: QueueWidgetButton) -> some View {
        switch button {
        case .startNext:
            EmptyView()
        case .pause:
            LiveActivityIntentButton(
                title: "Pause",
                intent: PauseResumeFocusIntent(),
                prominent: false,
                accessibilityLabel: "Pause focus"
            )
        case .resume:
            LiveActivityIntentButton(
                title: "Resume",
                intent: PauseResumeFocusIntent(),
                prominent: true,
                accessibilityLabel: "Resume focus"
            )
        case .done:
            LiveActivityIntentButton(
                title: "Done",
                intent: CompleteTaskIntent(),
                prominent: true,
                accessibilityLabel: "Mark block done"
            )
        case .extendFive:
            LiveActivityIntentButton(
                title: "+5",
                intent: ExtendFocusIntent(),
                prominent: false,
                accessibilityLabel: "Add five minutes"
            )
        }
    }
}

private struct LiveActivityDoneButton: View {
    var body: some View {
        LiveActivityIntentButton(
            title: "Done",
            intent: CompleteTaskIntent(),
            prominent: true,
            accessibilityLabel: "Mark block done",
            minHeight: 26,
            fontSize: 12,
            cornerRadius: 8
        )
    }
}

private struct LiveActivityIntentButton<I: AppIntent>: View {
    let title: String
    let intent: I
    var prominent: Bool
    var accessibilityLabel: String
    var minHeight: CGFloat = 34
    var fontSize: CGFloat = 14
    var cornerRadius: CGFloat = 12

    var body: some View {
        Button(intent: intent) {
            Text(title)
                .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                .foregroundStyle(prominent ? QueueColors.dark(.onPrimary) : QueueColors.dark(.textPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: minHeight)
                .background(
                    prominent ? QueueColors.dark(.primary) : QueueColors.dark(.surface),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .invalidatableContent()
        .accessibilityLabel(accessibilityLabel)
    }
}

private func focusIsTimeUp(_ context: ActivityViewContext<FocusActivityAttributes>) -> Bool {
    FocusActivityChrome.isTimeUp(
        state: context.state.session.state,
        remaining: context.state.remaining(),
        isStale: context.isStale
    )
}

private func focusButtons(_ context: ActivityViewContext<FocusActivityAttributes>) -> [QueueWidgetButton] {
    if focusIsTimeUp(context) {
        return QueueWidgetChromeState.buttons(for: .expired)
    }
    let chrome = QueueWidgetChromeState.make(
        focus: context.state.focusSnapshot(),
        queue: nil,
        at: Date()
    )
    return QueueWidgetChromeState.buttons(for: chrome)
}

private extension FocusActivityAttributes.ContentState {
    func focusSnapshot() -> FocusWidgetSnapshot {
        FocusWidgetSnapshot(
            taskID: session.taskID,
            taskTitle: taskTitle,
            difficultyDisplayName: difficultyDisplayName,
            estimatedDuration: estimatedDuration,
            session: session
        )
    }
}
#endif
