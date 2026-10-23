import WidgetKit
import SwiftUI
import QueueCore

struct FocusTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusTimerEntry {
        FocusTimerEntry(date: Date(), focus: nil, queue: .previewReady)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusTimerEntry) -> Void) {
        let focus = FocusActivityStore.load()
        let queue = QueueActivityStore.load()
        if context.isPreview, focus == nil, queue == nil {
            completion(FocusTimerEntry(date: Date(), focus: nil, queue: .previewReady))
            return
        }
        completion(FocusTimerEntry(date: Date(), focus: activeFocus(focus), queue: queue))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusTimerEntry>) -> Void) {
        let now = Date()
        let queue = QueueActivityStore.load()
        guard let snapshot = FocusActivityStore.load(), snapshot.isActivelyTiming else {
            let entry = FocusTimerEntry(date: now, focus: nil, queue: queue)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }

        // Clock uses Text(timerInterval:) so it keeps ticking without the app.
        // Timeline only refreshes for progress-ring / state changes.
        var entries: [FocusTimerEntry] = [FocusTimerEntry(date: now, focus: snapshot, queue: queue)]
        if snapshot.session.state == .running, let end = snapshot.runningEndDate(at: now) {
            // Re-render at expiry so Time's up controls can take over.
            entries.append(FocusTimerEntry(date: end, focus: snapshot, queue: queue))
            let mid = now.addingTimeInterval(min(60, max(15, end.timeIntervalSince(now) / 4)))
            if mid < end {
                entries.insert(FocusTimerEntry(date: mid, focus: snapshot, queue: queue), at: 1)
            }
            entries.sort { $0.date < $1.date }
            completion(Timeline(entries: entries, policy: .after(end.addingTimeInterval(1))))
        } else {
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(5 * 60))))
        }
    }

    private func activeFocus(_ snapshot: FocusWidgetSnapshot?) -> FocusWidgetSnapshot? {
        guard let snapshot, snapshot.isActivelyTiming else { return nil }
        return snapshot
    }
}

struct FocusTimerEntry: TimelineEntry {
    let date: Date
    let focus: FocusWidgetSnapshot?
    let queue: QueueWidgetSnapshot?
}

struct FocusTimerWidget: Widget {
    let kind = QueueWidgetReload.homeKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FocusTimerProvider()) { entry in
            FocusTimerWidgetView(entry: entry)
        }
        .configurationDisplayName("Focus timer")
        .description("See the next block, start it, and mark it done from the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct FocusTimerLockScreenWidget: Widget {
    let kind = QueueWidgetReload.lockScreenKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FocusTimerProvider()) { entry in
            LockScreenFocusView(entry: entry)
        }
        .configurationDisplayName("Focus timer")
        .description("Glanceable focus countdown.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

private struct LockScreenFocusView: View {
    var entry: FocusTimerEntry
    @Environment(\.widgetFamily) private var family

    private var chrome: QueueWidgetChrome {
        QueueWidgetChromeState.make(focus: entry.focus, queue: entry.queue, at: entry.date)
    }

    var body: some View {
        Group {
            if let snapshot = entry.focus, snapshot.isActivelyTiming {
                active(snapshot)
            } else {
                idle
            }
        }
        // Lock Screen and Watch Smart Stack stay vibrant. Tint follows the shared theme.
        .containerBackground(for: .widget) { Color.clear }
        .tint(QueueColors.dark(.primary))
        .dynamicTypeSize(.xSmall ... .accessibility2)
    }

    @ViewBuilder
    private func active(_ snapshot: FocusWidgetSnapshot) -> some View {
        switch family {
        case .accessoryCircular:
            ZStack {
                Gauge(value: snapshot.progress(at: entry.date)) {
                    Text("Focus")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .widgetAccentable()
                if snapshot.session.state == .running,
                   let end = snapshot.runningEndDate(at: entry.date),
                   snapshot.remaining(at: entry.date) > 0 {
                    Text(timerInterval: entry.date...end, countsDown: true)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5)
                        .widgetAccentable()
                } else {
                    Text(FocusTimerFormatting.clock(snapshot.remaining(at: entry.date)))
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .widgetAccentable()
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(focusAccessibility(snapshot))
        case .accessoryInline:
            Group {
                if snapshot.session.state == .running,
                   let end = snapshot.runningEndDate(at: entry.date),
                   snapshot.remaining(at: entry.date) > 0 {
                    Text(timerInterval: entry.date...end, countsDown: true)
                    + Text(" · \(snapshot.taskTitle)")
                } else {
                    Text("\(FocusTimerFormatting.clock(snapshot.remaining(at: entry.date))) · \(snapshot.taskTitle)")
                }
            }
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(focusAccessibility(snapshot))
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.taskTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                LiveCountdownText(snapshot: snapshot, at: entry.date, fontSize: 18, color: .primary)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(focusAccessibility(snapshot))
        }
    }

    @ViewBuilder
    private var idle: some View {
        switch chrome {
        case .ready(let next):
            ready(next)
        case .empty:
            empty
        case .needsLaunch, .focusing, .paused, .expired:
            empty
        }
    }

    @ViewBuilder
    private func ready(_ next: QueueWidgetNow) -> some View {
        let spoken = QueueWidgetFormatting.nextTaskSpoken(title: next.title, duration: next.duration)
        switch family {
        case .accessoryCircular:
            Gauge(value: todayFraction) {
                Text("Queue")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(todaySpoken). \(spoken)")
        case .accessoryInline:
            Text("Next: \(next.title)")
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
                .accessibilityLabel(spoken)
        default:
            Text(QueueWidgetFormatting.lockScreenNextLine(title: next.title, duration: next.duration))
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.65)
                .widgetAccentable()
                .accessibilityLabel(spoken)
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryCircular:
            Text(chrome == .empty ? "Clear" : "Queue")
                .font(.system(size: 12, weight: .semibold))
                .minimumScaleFactor(0.5)
                .widgetAccentable()
                .accessibilityLabel(chrome == .empty ? "Queue is clear" : "Open Queue")
        case .accessoryInline:
            Text(chrome == .empty ? "Queue is clear" : "Open Queue")
                .widgetAccentable()
        default:
            Text(chrome == .empty ? "Queue is clear" : "Open Queue")
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .widgetAccentable()
        }
    }

    private func focusAccessibility(_ snapshot: FocusWidgetSnapshot) -> String {
        let status: String
        switch snapshot.session.state {
        case .paused:
            status = "paused"
        case .expired:
            status = "time's up"
        default:
            status = snapshot.remaining(at: entry.date) <= 0 ? "time's up" : "focusing"
        }
        return QueueWidgetFormatting.focusAccessibility(
            title: snapshot.taskTitle,
            status: status,
            remaining: snapshot.remaining(at: entry.date)
        )
    }

    private var todaySpoken: String {
        QueueWidgetFormatting.todayAccessibility(
            done: entry.queue?.doneToday ?? 0,
            planned: entry.queue?.plannedToday ?? 0
        )
    }

    private var todayFraction: Double {
        let planned = entry.queue?.plannedToday ?? 0
        guard planned > 0 else { return 0 }
        return min(1, Double(entry.queue?.doneToday ?? 0) / Double(planned))
    }
}

// MARK: - Rendering

/// Full color uses the dark column of `QueueColors`. Accented (tinted and clear)
/// and vibrant (Lock Screen) leave the system to tint hierarchical styles.
struct WidgetPalette {
    var mode: WidgetRenderingMode

    var fullColor: Bool { mode == .fullColor }

    var textPrimary: Color { fullColor ? QueueColors.dark(.textPrimary) : .primary }
    var textSecondary: Color { fullColor ? QueueColors.dark(.textSecondary) : .secondary }
    /// Honey from the selected theme's dark column. Text on a honey fill uses `QueueColors.dark(.onAccent)`.
    var accent: Color { fullColor ? QueueColors.dark(.accent) : .primary }
    var onPrimary: Color { fullColor ? QueueColors.dark(.onPrimary) : .primary }
    var background: Color { QueueColors.dark(.background) }

    var primaryFill: Color {
        fullColor ? QueueColors.dark(.primary) : Color.primary.opacity(0.22)
    }

    var secondaryFill: Color {
        fullColor ? QueueColors.dark(.surface) : Color.primary.opacity(0.12)
    }

    var track: Color {
        fullColor ? QueueColors.dark(.textPrimary).opacity(0.18) : Color.primary.opacity(0.2)
    }

    /// In-progress rings are terracotta. Honey is the completed ring in dark mode only.
    /// Light mode, and tinted or vibrant Lock Screen styles, stay on primary.
    func ringColor(completed: Bool, colorScheme: ColorScheme) -> Color {
        guard fullColor else { return .primary }
        let honey = FocusActivityChrome.ringUsesHoney(isComplete: completed, isDark: colorScheme == .dark)
        let role: QueueColorRole = honey ? .accent : .primary
        if colorScheme == .dark {
            return QueueColors.dark(role)
        }
        return QueueColors.concrete(
            role,
            theme: QueueThemeStore.current(),
            scheme: .light,
            increasedContrast: false
        )
    }
}

/// Pins the dark column while a widget is full color. Tinted, clear, and vibrant keep the system scheme.
struct WidgetFullColorScheme: ViewModifier {
    @Environment(\.widgetRenderingMode) private var renderingMode

    @ViewBuilder
    func body(content: Content) -> some View {
        if renderingMode == .fullColor {
            content.environment(\.colorScheme, .dark)
        } else {
            content
        }
    }
}

enum WidgetCompanionState {
    case idle, working, paused, expired
}

/// Static companion frames. Animation stays out of the widget.
enum WidgetCompanionPose {
    case idle
    case working
    case done

    var assetName: String {
        switch self {
        case .idle: return "CompanionIdle"
        case .working: return "CompanionWorking"
        case .done: return "CompanionDone"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .idle: return "Companion resting"
        case .working: return "Companion focusing"
        case .done: return "Companion finished"
        }
    }

    static func pose(for state: WidgetCompanionState) -> WidgetCompanionPose {
        switch state {
        case .idle, .paused: return .idle
        case .working: return .working
        case .expired: return .done
        }
    }
}

struct WidgetCompanionBadge: View {
    let state: WidgetCompanionState
    let progress: Double
    var diameter: CGFloat = 52

    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme

    private var palette: WidgetPalette { WidgetPalette(mode: renderingMode) }
    private var pose: WidgetCompanionPose { WidgetCompanionPose.pose(for: state) }
    private var ringColor: Color {
        palette.ringColor(completed: state == .expired, colorScheme: colorScheme)
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(palette.track, lineWidth: max(CGFloat(2), diameter * 0.06))
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(
                    ringColor,
                    style: StrokeStyle(lineWidth: max(CGFloat(2), diameter * 0.06), lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
            companionImage
                .padding(diameter * 0.08)
        }
        .frame(width: diameter, height: diameter)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch state {
        case .paused: return "Companion paused"
        default: return pose.accessibilityLabel
        }
    }

    @ViewBuilder
    private var companionImage: some View {
        if #available(iOS 18.0, *) {
            // Apply while the value is still an Image. Luminance survives tinted and clear styles.
            Image(pose.assetName)
                .resizable()
                .interpolation(.high)
                .widgetAccentedRenderingMode(.accentedDesaturated)
                .scaledToFit()
        } else {
            Image(pose.assetName)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        }
    }
}

extension QueueWidgetSnapshot {
    static var previewReady: QueueWidgetSnapshot {
        let now = Date()
        return QueueWidgetSnapshot(
            now: QueueWidgetNow(
                id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID(),
                title: "Update résumé",
                duration: 15 * 60,
                difficulty: .medium
            ),
            upNext: [
                QueueWidgetUpcoming(id: UUID(), title: "Reply to Alex", duration: 15 * 60),
                QueueWidgetUpcoming(id: UUID(), title: "Sketch the widget", duration: 20 * 60),
                QueueWidgetUpcoming(id: UUID(), title: "Stretch", duration: 15 * 60)
            ],
            doneToday: 3,
            plannedToday: 6,
            minutesFocusedToday: 45,
            updatedAt: now
        )
    }
}

extension FocusWidgetSnapshot {
    static var placeholder: FocusWidgetSnapshot {
        galleryPlaceholder()
    }

    static func preview(state: FocusTimerState, at now: Date = Date()) -> FocusWidgetSnapshot {
        var snapshot = galleryPlaceholder(at: now)
        snapshot.session.state = state
        switch state {
        case .paused:
            snapshot.session.accumulatedActive = 5 * 60
            snapshot.session.segmentStart = now
        case .expired:
            snapshot.session.accumulatedActive = snapshot.session.plannedDuration
            snapshot.session.segmentStart = now
        case .running, .idle, .completed:
            break
        }
        return snapshot
    }
}

extension QueueWidgetSnapshot {
    static var previewEmpty: QueueWidgetSnapshot {
        QueueWidgetSnapshot(
            now: nil,
            upNext: [],
            doneToday: 0,
            plannedToday: 0,
            minutesFocusedToday: 0,
            updatedAt: Date()
        )
    }
}

struct FocusTimerWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            Group {
                home(.ready, .systemSmall)
                home(.ready, .systemMedium)
                home(.ready, .systemLarge)
                home(.focusing, .systemSmall)
                home(.focusing, .systemMedium)
                home(.focusing, .systemLarge)
                home(.paused, .systemMedium)
                home(.expired, .systemLarge)
                home(.empty, .systemSmall)
                home(.needsLaunch, .systemMedium)
            }
            Group {
                home(.ready, .systemMedium)
                    .environment(\.colorScheme, .light)
                home(.ready, .systemMedium)
                    .environment(\.colorScheme, .dark)
                home(.focusing, .systemMedium)
                    .environment(\.widgetRenderingMode, .accented)
                home(.ready, .systemLarge)
                    .environment(\.widgetRenderingMode, .accented)
                lock(.ready, .accessoryRectangular)
                lock(.ready, .accessoryInline)
                lock(.ready, .accessoryCircular)
                lock(.focusing, .accessoryRectangular)
                    .environment(\.widgetRenderingMode, .vibrant)
                lock(.focusing, .accessoryCircular)
                    .environment(\.widgetRenderingMode, .vibrant)
                lock(.empty, .accessoryRectangular)
                    .environment(\.widgetRenderingMode, .vibrant)
            }
            lock(.focusing, .accessoryInline)
                .environment(\.widgetRenderingMode, .vibrant)
        }
    }

    private enum Sample {
        case needsLaunch, empty, ready, focusing, paused, expired
    }

    private static func entry(_ sample: Sample) -> FocusTimerEntry {
        switch sample {
        case .needsLaunch:
            return FocusTimerEntry(date: .now, focus: nil, queue: nil)
        case .empty:
            return FocusTimerEntry(date: .now, focus: nil, queue: .previewEmpty)
        case .ready:
            return FocusTimerEntry(date: .now, focus: nil, queue: .previewReady)
        case .focusing:
            return FocusTimerEntry(date: .now, focus: .placeholder, queue: .previewReady)
        case .paused:
            return FocusTimerEntry(date: .now, focus: .preview(state: .paused), queue: .previewReady)
        case .expired:
            return FocusTimerEntry(date: .now, focus: .preview(state: .expired), queue: .previewReady)
        }
    }

    private static func home(_ sample: Sample, _ family: WidgetFamily) -> some View {
        FocusTimerWidgetView(entry: entry(sample))
            .previewContext(WidgetPreviewContext(family: family))
    }

    private static func lock(_ sample: Sample, _ family: WidgetFamily) -> some View {
        LockScreenFocusView(entry: entry(sample))
            .previewContext(WidgetPreviewContext(family: family))
    }
}
