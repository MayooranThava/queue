import Foundation

public struct CalendarEvent: Identifiable, Sendable, Equatable {
    public let id: String
    public let sourceProvider: String
    public let calendarID: String
    public let start: Date
    public let end: Date
    public let title: String?
    public let isAllDay: Bool
    public let isCancelled: Bool
    public let busy: Bool

    public init(
        id: String,
        sourceProvider: String,
        calendarID: String,
        start: Date,
        end: Date,
        title: String? = nil,
        isAllDay: Bool = false,
        isCancelled: Bool = false,
        busy: Bool = true
    ) {
        self.id = id
        self.sourceProvider = sourceProvider
        self.calendarID = calendarID
        self.start = start
        self.end = end
        self.title = title
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
        self.busy = busy
    }
}

public struct TimeGap: Sendable, Equatable {
    public let start: Date
    public let end: Date

    public var duration: TimeInterval {
        end.timeIntervalSince(start)
    }
}

public struct SmartGapSuggestion: Sendable, Equatable {
    public let taskID: UUID
    public let taskTitle: String
    public let estimatedDuration: TimeInterval
    public let gap: TimeGap
    public let breaksFIFOOrder: Bool
    public let explanation: String
}

/// Deterministic Smart Gaps algorithm (no AI).
public struct SmartGapsEngine: Sendable {
    public var preparationBuffer: TimeInterval

    public init(preparationBuffer: TimeInterval = 5 * 60) {
        self.preparationBuffer = preparationBuffer
    }

    public func mergeBusyIntervals(
        events: [CalendarEvent],
        in range: TimeGap
    ) -> [TimeGap] {
        let relevant = events.filter { event in
            guard !event.isCancelled, event.busy, !event.isAllDay else { return false }
            return event.end > range.start && event.start < range.end
        }
        .map { event in
            TimeGap(
                start: max(event.start, range.start),
                end: min(event.end, range.end)
            )
        }
        .sorted { $0.start < $1.start }

        var merged: [TimeGap] = []
        for interval in relevant {
            guard let last = merged.last else {
                merged.append(interval)
                continue
            }
            if interval.start <= last.end {
                merged[merged.count - 1] = TimeGap(
                    start: last.start,
                    end: max(last.end, interval.end)
                )
            } else {
                merged.append(interval)
            }
        }
        return merged
    }

    public func freeGaps(busy: [TimeGap], in range: TimeGap) -> [TimeGap] {
        var gaps: [TimeGap] = []
        var cursor = range.start
        for block in busy {
            if block.start > cursor {
                gaps.append(TimeGap(start: cursor, end: block.start))
            }
            cursor = max(cursor, block.end)
        }
        if cursor < range.end {
            gaps.append(TimeGap(start: cursor, end: range.end))
        }
        return gaps
    }

    /// Suggests the earliest FIFO-fitting task, or the best shorter task with explanation.
    public func suggest(
        tasks: [QueueTask],
        events: [CalendarEvent],
        from now: Date,
        lookAhead: TimeInterval = 8 * 3600
    ) -> SmartGapSuggestion? {
        let range = TimeGap(start: now, end: now.addingTimeInterval(lookAhead))
        let busy = mergeBusyIntervals(events: events, in: range)
        let gaps = freeGaps(busy: busy, in: range)
        let queued = tasks
            .filter { $0.status == .queued }
            .sorted { $0.queuePosition < $1.queuePosition }
        guard let firstGap = gaps.first else { return nil }

        let usable = TimeGap(
            start: firstGap.start,
            end: firstGap.end.addingTimeInterval(-preparationBuffer)
        )
        guard usable.duration > 0 else { return nil }

        if let head = queued.first, head.estimatedDuration <= usable.duration {
            return SmartGapSuggestion(
                taskID: head.id,
                taskTitle: head.title,
                estimatedDuration: head.estimatedDuration,
                gap: usable,
                breaksFIFOOrder: false,
                explanation: "Next in your queue fits the \(format(usable.duration)) gap before your next commitment."
            )
        }

        guard let fit = queued.first(where: { $0.estimatedDuration <= usable.duration }) else {
            return nil
        }
        let headTitle = queued.first?.title ?? "your next task"
        return SmartGapSuggestion(
            taskID: fit.id,
            taskTitle: fit.title,
            estimatedDuration: fit.estimatedDuration,
            gap: usable,
            breaksFIFOOrder: fit.id != queued.first?.id,
            explanation: "“\(fit.title)” fits this \(format(usable.duration)) gap; “\(headTitle)” needs more time. Confirm to start out of order."
        )
    }

    private func format(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours)h" : "\(hours)h \(rem)m"
    }
}
