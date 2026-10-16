import Foundation

/// Cross-process snapshot of the active focus session for Queue UI, widgets, and Live Activities.
/// Remaining time is always derived from `session` timestamps — never stored as a tick counter.
public struct FocusWidgetSnapshot: Codable, Sendable, Equatable {
    public var taskID: UUID
    public var taskTitle: String
    public var difficultyDisplayName: String
    public var estimatedDuration: TimeInterval
    public var session: FocusSession
    public var updatedAt: Date

    public init(
        taskID: UUID,
        taskTitle: String,
        difficultyDisplayName: String,
        estimatedDuration: TimeInterval,
        session: FocusSession,
        updatedAt: Date = Date()
    ) {
        self.taskID = taskID
        self.taskTitle = taskTitle
        self.difficultyDisplayName = difficultyDisplayName
        self.estimatedDuration = estimatedDuration
        self.session = session
        self.updatedAt = updatedAt
    }

    public func remaining(at now: Date = Date()) -> TimeInterval {
        session.remaining(at: now)
    }

    public func progress(at now: Date = Date()) -> Double {
        let total = max(1, session.totalPlanned)
        return session.remaining(at: now) / total
    }

    /// Live countdown end while running. `nil` when paused/expired — callers show a static clock.
    public func runningEndDate(at now: Date = Date()) -> Date? {
        session.runningEndDate(at: now)
    }

    public var isActivelyTiming: Bool {
        switch session.state {
        case .running, .paused, .expired:
            return true
        case .idle, .completed:
            return false
        }
    }
}

/// Formats countdown labels consistently across Focus, Queue, and widgets.
public enum FocusTimerFormatting {
    public static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public static func spoken(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded(.up)))
        let minutes = total / 60
        let seconds = total % 60
        if minutes == 0 { return "\(seconds) seconds" }
        if seconds == 0 { return "\(minutes) minutes" }
        return "\(minutes) minutes \(seconds) seconds"
    }
}
