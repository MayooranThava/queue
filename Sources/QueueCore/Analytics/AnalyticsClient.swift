import Foundation

/// Privacy-conscious local analytics boundary. No network transport in MVP.
public protocol AnalyticsClient: Sendable {
    func track(_ event: AnalyticsEvent)
}

public enum AnalyticsEvent: Sendable, Equatable {
    case onboardingStarted
    case onboardingCompleted
    case taskCreated(taskID: UUID)
    case taskStarted(taskID: UUID)
    case taskCompleted(taskID: UUID)
    case taskExtended(taskID: UUID)
    case taskMovedToReview(taskID: UUID)
    case focusSessionCompleted(taskID: UUID)
    case calendarConnected(provider: String)
    case smartGapSuggested(taskID: UUID)
    case smartGapAccepted(taskID: UUID)
    case dailyGoalReached

    public var name: String {
        switch self {
        case .onboardingStarted: return "onboarding_started"
        case .onboardingCompleted: return "onboarding_completed"
        case .taskCreated: return "task_created"
        case .taskStarted: return "task_started"
        case .taskCompleted: return "task_completed"
        case .taskExtended: return "task_extended"
        case .taskMovedToReview: return "task_moved_to_review"
        case .focusSessionCompleted: return "focus_session_completed"
        case .calendarConnected: return "calendar_connected"
        case .smartGapSuggested: return "smart_gap_suggested"
        case .smartGapAccepted: return "smart_gap_accepted"
        case .dailyGoalReached: return "daily_goal_reached"
        }
    }
}

public final class InMemoryAnalyticsClient: AnalyticsClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [AnalyticsEvent] = []

    public init() {}

    public func track(_ event: AnalyticsEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    public var events: [AnalyticsEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
