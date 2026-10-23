import WidgetKit
import SwiftUI
import AppIntents
import QueueCore

struct FocusTimerWidgetView: View {
    var entry: FocusTimerEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    private var chrome: QueueWidgetChrome {
        QueueWidgetChromeState.make(focus: entry.focus, queue: entry.queue, at: entry.date)
    }

    private var palette: WidgetPalette { WidgetPalette(mode: renderingMode) }

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
        .dynamicTypeSize(.xSmall ... .accessibility2)
        // Background stays in the container so tinted, clear, and StandBy can remove it.
        .containerBackground(for: .widget) {
            renderingMode == .fullColor ? palette.background : Color.clear
        }
        .modifier(WidgetFullColorScheme())
        .widgetURL(entry.focus?.isActivelyTiming == true ? QueueDeepLink.focus : QueueDeepLink.queue)
    }

    // MARK: - Families

    private var smallLayout: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsLiveClock {
                header(titleLines: 1)
                HStack(alignment: .center, spacing: 8) {
                    countdown(fontSize: 28)
                    Spacer(minLength: 0)
                    companion(diameter: 48)
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    header(titleLines: 2)
                    Spacer(minLength: 0)
                    companion(diameter: 40)
                }
            }
            Spacer(minLength: 0)
            controls
        }
        .padding(12)
    }

    private var mediumLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    header(titleLines: 2)
                    if !showsLiveClock {
                        Spacer(minLength: 0)
                        companion(diameter: 44)
                    }
                }
                if showsLiveClock {
                    HStack(alignment: .center, spacing: 8) {
                        countdown(fontSize: 28)
                        companion(diameter: 52)
                    }
                }
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
                companion(diameter: 72)
            }

            upNextList(limit: 5)
            Spacer(minLength: 0)
            progressFooter
            if let finish = projectedFinishText {
                Text(finish)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
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
            VStack(alignment: .leading, spacing: 2) {
                wordmark
                Text("Open Queue")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Text("Your next block will show here.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Open Queue. Your next block will show here.")
        case .empty:
            VStack(alignment: .leading, spacing: 2) {
                wordmark
                Text("Queue is clear")
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                Text("Add a task to get started.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Queue is clear. Add a task to get started.")
        case .ready(let next):
            VStack(alignment: .leading, spacing: 4) {
                wordmark
                Text(next.title)
                    .font(.system(size: family == .systemSmall ? 17 : 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(titleLines)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 8) {
                    durationChip(next.duration)
                    if family == .systemSmall {
                        Spacer(minLength: 0)
                        todayCount
                    }
                }
            }
        case .focusing, .paused, .expired:
            if let focus = entry.focus {
                VStack(alignment: .leading, spacing: 2) {
                    Text(focus.taskTitle)
                        .font(.system(size: family == .systemSmall ? 15 : 17, weight: .semibold, design: .rounded))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(titleLines)
                        .minimumScaleFactor(0.7)
                    Text(statusLine(focus))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                        .widgetAccentable(chrome == .expired)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(focus.taskTitle), \(statusLine(focus))")
            }
        }
    }

    private var wordmark: some View {
        Text("Queue")
            .font(.system(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(palette.textSecondary)
    }

    private func durationChip(_ duration: TimeInterval) -> some View {
        Text(QueueWidgetFormatting.minutesLabel(duration))
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(palette.onPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(palette.primaryFill, in: Capsule())
            .accessibilityLabel(QueueWidgetFormatting.spokenMinutes(duration))
    }

    private var todayCount: some View {
        let done = entry.queue?.doneToday ?? 0
        let planned = entry.queue?.plannedToday ?? 0
        return Text(QueueWidgetFormatting.todayCount(done: done, planned: planned))
            .font(.system(size: 12, weight: .medium, design: .rounded).monospacedDigit())
            .foregroundStyle(palette.textSecondary)
            .accessibilityLabel(QueueWidgetFormatting.todayAccessibility(done: done, planned: planned))
    }

    private func upNextList(limit: Int) -> some View {
        let rows = Array((entry.queue?.upNext ?? []).prefix(limit))
        return VStack(alignment: .leading, spacing: 6) {
            Text("Up next")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(palette.textSecondary)
            if rows.isEmpty {
                Text(chrome == .empty || chrome == .needsLaunch ? "Nothing queued" : "Nothing after this")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(rows) { row in
                    HStack(spacing: 6) {
                        Text(row.title)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(QueueWidgetFormatting.minutesLabel(row.duration))
                            .monospacedDigit()
                    }
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(QueueWidgetFormatting.rowAccessibility(title: row.title, duration: row.duration))
                }
            }
        }
    }

    private var progressFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            todayCount
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.track)
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: max(0, proxy.size.width * todayFraction))
                        .widgetAccentable()
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
            LiveCountdownText(snapshot: focus, at: entry.date, fontSize: fontSize, color: palette.textPrimary)
                .widgetAccentable()
        }
    }

    private func companion(diameter: CGFloat) -> some View {
        WidgetCompanionBadge(state: companionState, progress: ringProgress, diameter: diameter)
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
        chrome == .expired ? palette.accent : palette.textSecondary
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

    @Environment(\.widgetRenderingMode) private var renderingMode

    private var palette: WidgetPalette { WidgetPalette(mode: renderingMode) }

    var body: some View {
        Button(intent: intent) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(prominent ? palette.onPrimary : palette.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(
                    prominent ? palette.primaryFill : palette.secondaryFill,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )
        }
        .buttonStyle(.plain)
        // Primary action takes the accent in tinted, clear, and vibrant styles.
        .widgetAccentable(prominent)
        .invalidatableContent()
        .accessibilityLabel(accessibilityLabel)
    }
}
