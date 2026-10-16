import Foundation

public enum TaskStatus: String, Codable, Sendable, CaseIterable, Equatable {
    case queued
    case active
    case paused
    case completed
    case expired
    case review
    case skipped
    case archived
}

public enum TaskTransitionError: Error, Equatable, Sendable {
    case invalidTransition(from: TaskStatus, to: TaskStatus)
    case activeTaskAlreadyExists
    case taskNotFound
    case cannotReorderTerminalTask
}

public enum TaskTransition: Sendable {
    case start
    case pause
    case resume
    case complete
    case expire
    case moveToReview
    case skip
    case requeue
    case archive
    case continueWithoutTimer
    case undoComplete
}

public enum TaskStateMachine {
    public static func canTransition(from: TaskStatus, applying transition: TaskTransition) -> Bool {
        switch (from, transition) {
        case (.queued, .start): return true
        case (.active, .pause), (.active, .complete), (.active, .expire),
             (.active, .moveToReview), (.active, .skip): return true
        case (.paused, .resume), (.paused, .complete), (.paused, .expire),
             (.paused, .moveToReview), (.paused, .skip): return true
        case (.expired, .continueWithoutTimer), (.expired, .moveToReview),
             (.expired, .skip), (.expired, .start): return true
        case (.review, .requeue), (.review, .skip), (.review, .archive): return true
        case (.completed, .archive), (.completed, .undoComplete): return true
        case (.skipped, .archive), (.skipped, .requeue): return true
        default: return false
        }
    }

    public static func apply(from: TaskStatus, transition: TaskTransition) throws -> TaskStatus {
        guard canTransition(from: from, applying: transition) else {
            let target = tentativeTarget(for: transition)
            throw TaskTransitionError.invalidTransition(from: from, to: target)
        }
        return tentativeTarget(for: transition)
    }

    private static func tentativeTarget(for transition: TaskTransition) -> TaskStatus {
        switch transition {
        case .start, .resume, .continueWithoutTimer: return .active
        case .pause: return .paused
        case .complete: return .completed
        case .expire: return .expired
        case .moveToReview: return .review
        case .skip: return .skipped
        case .requeue, .undoComplete: return .queued
        case .archive: return .archived
        }
    }
}
