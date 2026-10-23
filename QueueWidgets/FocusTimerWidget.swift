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
        .containerBackground(for: .widget) { Color.clear }
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
                if snapshot.session.state == .running,
                   let end = snapshot.runningEndDate(at: entry.date),
                   snapshot.remaining(at: entry.date) > 0 {
                    Text(timerInterval: entry.date...end, countsDown: true)
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                        .minimumScaleFactor(0.5)
                } else {
                    Text(FocusTimerFormatting.clock(snapshot.remaining(at: entry.date)))
                        .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                }
            }
        case .accessoryInline:
            if snapshot.session.state == .running,
               let end = snapshot.runningEndDate(at: entry.date),
               snapshot.remaining(at: entry.date) > 0 {
                Text(timerInterval: entry.date...end, countsDown: true)
                + Text(" · \(snapshot.taskTitle)")
            } else {
                Text("\(FocusTimerFormatting.clock(snapshot.remaining(at: entry.date))) · \(snapshot.taskTitle)")
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.taskTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                LiveCountdownText(snapshot: snapshot, at: entry.date, fontSize: 18)
            }
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
        switch family {
        case .accessoryCircular:
            Gauge(value: todayFraction) {
                Text("Queue")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel("\(entry.queue?.doneToday ?? 0) of \(entry.queue?.plannedToday ?? 0) done today")
        case .accessoryInline:
            Text("Next: \(next.title)")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("Next: \(next.title)")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text(QueueWidgetFormatting.minutesLabel(next.duration))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
            }
            .accessibilityLabel(QueueWidgetFormatting.nextTaskAccessibility(title: next.title, duration: next.duration))
        }
    }

    @ViewBuilder
    private var empty: some View {
        switch family {
        case .accessoryCircular:
            Image(systemName: "leaf.fill")
        case .accessoryInline:
            Text(chrome == .empty ? "Queue is clear" : "Queue")
        default:
            Text(chrome == .empty ? "Queue is clear" : "Open Queue")
                .font(.headline)
        }
    }

    private var todayFraction: Double {
        let planned = entry.queue?.plannedToday ?? 0
        guard planned > 0 else { return 0 }
        return min(1, Double(entry.queue?.doneToday ?? 0) / Double(planned))
    }
}

// MARK: - Widget-local visuals

enum WidgetCompanionState {
    case idle, working, paused, expired
}

struct WidgetCompanionBadge: View {
    let state: WidgetCompanionState
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(QueueColors.dark(.textPrimary).opacity(0.18), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(QueueColors.dark(.accent), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            ZStack {
                Capsule()
                    .fill(QueueColors.dark(.primary).opacity(0.9))
                    .frame(width: 28, height: 4)
                    .offset(y: 12)
                Circle()
                    .fill(QueueColors.dark(.textPrimary))
                    .frame(width: 14, height: 14)
                    .offset(y: -4)
                Capsule()
                    .fill(QueueColors.dark(.textPrimary))
                    .frame(width: 18, height: 12)
                    .offset(y: 6)
                RoundedRectangle(cornerRadius: 1)
                    .fill(QueueColors.dark(.background))
                    .frame(width: 12, height: 7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(QueueColors.dark(.accent).opacity(state == .working ? 0.7 : 0.25))
                            .padding(1.5)
                    )
                    .offset(y: 5)
            }
        }
        .frame(width: 52, height: 52)
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
        let now = Date()
        let session = FocusSession(
            taskID: UUID(),
            sessionStart: now,
            segmentStart: now,
            plannedDuration: 25 * 60,
            state: .running
        )
        return FocusWidgetSnapshot(
            taskID: session.taskID,
            taskTitle: "Ship the focus timer",
            difficultyDisplayName: "Medium",
            estimatedDuration: 25 * 60,
            session: session
        )
    }
}

struct FocusTimerWidget_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            FocusTimerWidgetView(entry: FocusTimerEntry(date: .now, focus: nil, queue: .previewReady))
                .previewContext(WidgetPreviewContext(family: .systemSmall))
            FocusTimerWidgetView(entry: FocusTimerEntry(date: .now, focus: nil, queue: .previewReady))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
            FocusTimerWidgetView(entry: FocusTimerEntry(date: .now, focus: nil, queue: .previewReady))
                .previewContext(WidgetPreviewContext(family: .systemLarge))
            FocusTimerWidgetView(entry: FocusTimerEntry(date: .now, focus: .placeholder, queue: .previewReady))
                .previewContext(WidgetPreviewContext(family: .systemMedium))
        }
    }
}
