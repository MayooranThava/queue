import WidgetKit
import SwiftUI
import QueueCore

struct FocusTimerProvider: TimelineProvider {
    func placeholder(in context: Context) -> FocusTimerEntry {
        FocusTimerEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (FocusTimerEntry) -> Void) {
        completion(FocusTimerEntry(date: Date(), snapshot: FocusActivityStore.load() ?? .placeholder))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FocusTimerEntry>) -> Void) {
        let now = Date()
        guard let snapshot = FocusActivityStore.load(), snapshot.isActivelyTiming else {
            let entry = FocusTimerEntry(date: now, snapshot: nil)
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(15 * 60))))
            return
        }

        // Clock uses Text(timerInterval:) so it keeps ticking without the app.
        // Timeline only refreshes for progress-ring / state changes.
        var entries: [FocusTimerEntry] = [FocusTimerEntry(date: now, snapshot: snapshot)]
        if snapshot.session.state == .running, let end = snapshot.runningEndDate(at: now) {
            // Re-render at expiry so paused/expired chrome can take over.
            entries.append(FocusTimerEntry(date: end, snapshot: snapshot))
            // Occasional mid-session refresh for the progress ring.
            let mid = now.addingTimeInterval(min(60, max(15, end.timeIntervalSince(now) / 4)))
            if mid < end {
                entries.insert(FocusTimerEntry(date: mid, snapshot: snapshot), at: 1)
            }
            entries.sort { $0.date < $1.date }
            completion(Timeline(entries: entries, policy: .after(end.addingTimeInterval(1))))
        } else {
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(5 * 60))))
        }
    }
}

struct FocusTimerEntry: TimelineEntry {
    let date: Date
    let snapshot: FocusWidgetSnapshot?
}

struct FocusTimerWidgetView: View {
    var entry: FocusTimerEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.isActivelyTiming {
                activeView(snapshot)
            } else {
                emptyView
            }
        }
        .containerBackground(for: .widget) {
            QueueWidgetColors.charcoal
        }
        .widgetURL(entry.snapshot?.isActivelyTiming == true ? QueueDeepLink.focus : QueueDeepLink.queue)
    }

    private func activeView(_ snapshot: FocusWidgetSnapshot) -> some View {
        let progress = snapshot.progress(at: entry.date)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(snapshot.taskTitle)
                        .font(.system(size: family == .systemSmall ? 13 : 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(QueueWidgetColors.ivory)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                    Text(statusLine(snapshot))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(QueueWidgetColors.ivory.opacity(0.55))
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                WidgetCompanionBadge(state: companionState(snapshot), progress: progress)
            }

            Spacer(minLength: 0)

            LiveCountdownText(
                snapshot: snapshot,
                at: entry.date,
                fontSize: family == .systemSmall ? 26 : 34
            )
        }
        .padding(14)
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Queue")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(QueueWidgetColors.sage)
            Text("No active focus")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(QueueWidgetColors.ivory)
            Text("Start a task to see the timer here.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(QueueWidgetColors.ivory.opacity(0.55))
            Spacer(minLength: 0)
            WidgetCompanionBadge(state: .idle, progress: 1)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(14)
    }

    private func statusLine(_ snapshot: FocusWidgetSnapshot) -> String {
        switch snapshot.session.state {
        case .paused: return "Paused"
        case .expired: return "Time’s up"
        default: return "\(snapshot.difficultyDisplayName) · focusing"
        }
    }

    private func companionState(_ snapshot: FocusWidgetSnapshot) -> WidgetCompanionState {
        switch snapshot.session.state {
        case .paused: return .paused
        case .expired: return .expired
        default: return .working
        }
    }
}

struct FocusTimerWidget: Widget {
    let kind = "FocusTimerWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FocusTimerProvider()) { entry in
            FocusTimerWidgetView(entry: entry)
        }
        .configurationDisplayName("Focus timer")
        .description("See your active Queue countdown on the Home Screen.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct FocusTimerLockScreenWidget: Widget {
    let kind = "FocusTimerLockScreenWidget"

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

    var body: some View {
        Group {
            if let snapshot = entry.snapshot, snapshot.isActivelyTiming {
                switch family {
                case .accessoryCircular:
                    ZStack {
                        Gauge(value: snapshot.progress(at: entry.date)) {
                            Text("Focus")
                        }
                        .gaugeStyle(.accessoryCircularCapacity)
                        if snapshot.session.state == .running,
                           let end = snapshot.runningEndDate(at: entry.date) {
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
                       let end = snapshot.runningEndDate(at: entry.date) {
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
            } else {
                switch family {
                case .accessoryCircular:
                    Image(systemName: "leaf.fill")
                case .accessoryInline:
                    Text("Queue · idle")
                default:
                    Text("No active focus")
                        .font(.headline)
                }
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }
}

// MARK: - Widget-local visuals

enum QueueWidgetColors {
    static let ivory = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let cream = Color(red: 0.96, green: 0.93, blue: 0.86)
    static let sage = Color(red: 0.78, green: 0.84, blue: 0.76)
    static let sageDeep = Color(red: 0.45, green: 0.55, blue: 0.48)
    static let charcoal = Color(red: 0.14, green: 0.15, blue: 0.16)
    static let reward = Color(red: 0.72, green: 0.82, blue: 0.28)
}

enum WidgetCompanionState {
    case idle, working, paused, expired
}

struct WidgetCompanionBadge: View {
    let state: WidgetCompanionState
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(QueueWidgetColors.ivory.opacity(0.12), lineWidth: 3)
            Circle()
                .trim(from: 0, to: CGFloat(min(1, max(0, progress))))
                .stroke(QueueWidgetColors.reward.opacity(0.9), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .rotationEffect(.degrees(-90))

            ZStack {
                Capsule()
                    .fill(Color(red: 0.42, green: 0.32, blue: 0.24).opacity(0.9))
                    .frame(width: 28, height: 4)
                    .offset(y: 12)
                Circle()
                    .fill(QueueWidgetColors.cream)
                    .frame(width: 14, height: 14)
                    .offset(y: -4)
                Capsule()
                    .fill(QueueWidgetColors.cream)
                    .frame(width: 18, height: 12)
                    .offset(y: 6)
                RoundedRectangle(cornerRadius: 1)
                    .fill(QueueWidgetColors.charcoal)
                    .frame(width: 12, height: 7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 0.5)
                            .fill(QueueWidgetColors.reward.opacity(state == .working ? 0.7 : 0.25))
                            .padding(1.5)
                    )
                    .offset(y: 5)
            }
        }
        .frame(width: 52, height: 52)
    }
}

private extension FocusWidgetSnapshot {
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
