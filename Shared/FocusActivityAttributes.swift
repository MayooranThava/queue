import Foundation
import QueueCore
#if canImport(ActivityKit)
import ActivityKit
#endif

#if canImport(ActivityKit)
/// Shared Live Activity payload — app starts it; widget extension renders it.
public struct FocusActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var session: FocusSession
        public var taskTitle: String
        public var difficultyDisplayName: String
        public var estimatedDuration: TimeInterval

        public init(
            session: FocusSession,
            taskTitle: String,
            difficultyDisplayName: String,
            estimatedDuration: TimeInterval
        ) {
            self.session = session
            self.taskTitle = taskTitle
            self.difficultyDisplayName = difficultyDisplayName
            self.estimatedDuration = estimatedDuration
        }

        public func remaining(at now: Date = Date()) -> TimeInterval {
            session.remaining(at: now)
        }

        public func progress(at now: Date = Date()) -> Double {
            let total = max(1, session.totalPlanned)
            return session.remaining(at: now) / total
        }
    }

    public var taskID: UUID

    public init(taskID: UUID) {
        self.taskID = taskID
    }
}
#endif
