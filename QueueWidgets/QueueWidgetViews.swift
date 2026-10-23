import WidgetKit
import SwiftUI
import AppIntents
import QueueCore

struct FocusTimerWidgetView: View {
    var entry: FocusTimerEntry
    @Environment(\.widgetFamily) private var family

    private var chrome: QueueWidgetChrome {
        QueueWidgetChromeState.make(focus: entry.focus, queue: entry.queue, at: entry.date)
    }

    var body: some View {
        Group {
            switch family {
            case .systemLarge:
                largeLayout
            case .systemMedium:
                mediumLayout
            default:
                smallLayout
            }
        }
        .containerBackground(for: .widget) {
            QueueColors.dark(.background)
        }
        .environment(\.colorScheme, .dark)
        .widgetURL(entry.focus?.isActivelyTiming == true ? QueueDeepLink.focus : QueueDeepLink.queue)
    }

    // MARK: - Families

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(titleLines: showsLiveClock ? 1 : 2)
            countdown(fontSize: 28)
            Spacer(minLength: 0)
            controls
        }
        .padding(12)
    }

    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                header(titleLines: 2)
                countdown(fontSize: 32)
                Spacer(minLength: 0)
                controls
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                upNextList(limit: showsLiveClock ? 2 : 3)
                Spacer(minLength: 0)
                progressFooter
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
    }

    private var largeLayout: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    header(titleLines: 2)
                    countdown(fontSize: 40)
                    controls
                }
                Spacer(minLength: 0)
                WidgetCompanionBadge(state: companionState, progress: ringProgress)
            }

            upNextList(limit: 5)
            Spacer(minLength: 0)
            progressFooter
            if let finish = projectedFinishText {
                Text(finish)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(QueueColors.dark(.textPrimary))
                    .accessibilityLabel(finish)
            }
        }
        .padding(16)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func header(titleLines: Int) -> some View {
        switch chrome {
        case .needsLaunch:
            wordmark
            Text("Open Queue")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(QueueColors.dark(.textPrimary))
            Text("Your next block will show here.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(QueueColors.dark(.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        case .empty:
            wordmark
            Text("Queue is clear")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(QueueColors.dark(.textPrimary))
            Text("Add a task to get started.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(QueueColors.dark(.textSecondary))
        case .ready(let next):
            wordmark
            Text(next.title)
                .font(.system(size: family == .systemSmall ? 17 : 18, weight: .semibold, design: .rounded))
                .foregroundStyle(QueueColors.dark(.textPrimary))
                .lineLimit(titleLines)
                .minimumScaleFactor(0.75)
            HStack(spacing: 8) {
                durationChip(next.duration)
                if family == .systemSmall {
                    Spacer(minLength: 0)
                    todayCount
                }
            }
        case .focusing, .paused, .expired:
            if let focus = entry.focus {
                Text(focus.taskTitle)
                    .font(.system(size: family == .systemSmall ? 15 : 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(QueueColors.dark(.textPrimary))
                    .lineLimit(titleLines)
                    .minimumScaleFactor(0.75)
                Text(statusLine(focus))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(statusColor)
                    .lineLimit(1)
            }
        }
    }

    private var wordmark: some View {
        Text("Queue")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(QueueColors.dark(.textSecondary))
    }

    private func durationChip(_ duration: TimeInterval) -> some View {
        Text(QueueWidgetFormatting.minutesLabel(duration))
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(QueueColors.dark(.onPrimary))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(QueueColors.dark(.primary), in: Capsule())
            .accessibilityLabel(QueueWidgetFormatting.minutesLabel(duration))
    }

    private var todayCount: some View {
        let done = entry.queue?.doneToday ?? 0
        let planned = entry.queue?.plannedToday ?? 0
        return Text(QueueWidgetFormatting.todayCount(done: done, planned: planned))
            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(QueueColors.dark(.textSecondary))
            .accessibilityLabel("\(done) of \(planned) done today")
    }

    private func upNextList(limit: Int) -> some View {
        let rows = Array((entry.queue?.upNext ?? []).prefix(limit))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Up next")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(QueueColors.dark(.textSecondary))
            if rows.isEmpty {
                Text(chrome == .empty || chrome == .needsLaunch ? "Nothing queued" : "Nothing after this")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(QueueColors.dark(.textSecondary))
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 6) {
                        Text(row.title)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(QueueWidgetFormatting.minutesLabel(row.duration))
                            .monospacedDigit()
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(QueueColors.dark(.textPrimary))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(row.title), \(QueueWidgetFormatting.minutesLabel(row.duration))")
                }
            }
        }
    }

    private var progressFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            todayCount
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(QueueColors.dark(.surface))
                    Capsule()
                        .fill(QueueColors.dark(.accent))
                        .frame(width: max(0, proxy.size.width * todayFraction))
                }
            }
            .frame(height: 6)
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var controls: some View {
        let buttons = QueueWidgetChromeState.buttons(for: chrome)
        if !buttons.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(buttons.enumerated()), id: \.offset) { item in
                    buttonView(item.element)
                }
            }
        }
    }

    @ViewBuilder
    private func buttonView(_ button: QueueWidgetButton) -> some View {
        switch button {
        case .startNext:
            WidgetIntentButton(
                title: "Start",
                intent: StartNextTaskIntent(),
                prominent: true,
                accessibilityLabel: startAccessibility
            )
        case .pause:
            WidgetIntentButton(
                title: "Pause",
                intent: PauseResumeFocusIntent(),
                prominent: false,
                accessibilityLabel: "Pause focus"
            )
        case .resume:
            WidgetIntentButton(
                title: "Resume",
                intent: PauseResumeFocusIntent(),
                prominent: true,
                accessibilityLabel: "Resume focus"
            )
        case .done:
            WidgetIntentButton(
                title: "Done",
                intent: CompleteTaskIntent(),
                prominent: true,
                accessibilityLabel: "Mark block done"
            )
        case .extendFive:
            WidgetIntentButton(
                title: "+5",
                intent: ExtendFocusIntent(),
                prominent: false,
                accessibilityLabel: "Add five minutes"
            )
        }
    }

    private var startAccessibility: String {
        if case .ready(let next) = chrome {
            return QueueWidgetFormatting.nextTaskAccessibility(title: next.title, duration: next.duration)
        }
        return "Start next task"
    }

    @ViewBuilder
    private func countdown(fontSize: CGFloat) -> some View {
        if showsLiveClock, let focus = entry.focus {
            LiveCountdownText(snapshot: focus, at: entry.date, fontSize: fontSize)
        }
    }

    private var showsLiveClock: Bool {
        guard let focus = entry.focus, focus.isActivelyTiming else { return false }
        switch chrome {
        case .focusing, .paused, .expired:
            return true
        case .needsLaunch, .empty, .ready:
            return false
        }
    }

    private var ringProgress: Double {
        if let focus = entry.focus, focus.isActivelyTiming {
            return focus.progress(at: entry.date)
        }
        return todayFraction
    }

    private var companionState: WidgetCompanionState {
        switch chrome {
        case .paused: return .paused
        case .expired: return .expired
        case .focusing: return .working
        case .ready, .empty, .needsLaunch: return .idle
        }
    }

    private var statusColor: Color {
        chrome == .expired ? QueueColors.dark(.accent) : QueueColors.dark(.textSecondary)
    }

    private func statusLine(_ snapshot: FocusWidgetSnapshot) -> String {
        switch chrome {
        case .paused: return "Paused"
        case .expired: return "Time’s up"
        default: return "\(snapshot.difficultyDisplayName) · focusing"
        }
    }

    private var todayFraction: Double {
        let planned = entry.queue?.plannedToday ?? 0
        guard planned > 0 else { return 0 }
        return min(1, Double(entry.queue?.doneToday ?? 0) / Double(planned))
    }

    private var projectedFinishText: String? {
        guard let queue = entry.queue,
              let finish = QueueWidgetProjection.projectedFinish(queue: queue, focus: entry.focus, at: entry.date)
        else { return nil }
        return "Done by \(finish.formatted(date: .omitted, time: .shortened))"
    }
}

private struct WidgetIntentButton<I: AppIntent>: View {
    let title: String
    let intent: I
    var prominent: Bool
    var accessibilityLabel: String

    var body: some View {
        Button(intent: intent) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(prominent ? QueueColors.dark(.onPrimary) : QueueColors.dark(.textPrimary))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    prominent ? QueueColors.dark(.primary) : QueueColors.dark(.surface),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        .invalidatableContent()
        .accessibilityLabel(accessibilityLabel)
    }
}
