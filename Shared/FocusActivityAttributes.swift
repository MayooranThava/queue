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
        /// Show companion preference. Missing on older payloads, which stay visible.
        public var showsCompanion: Bool
        /// Following queued block, already trimmed. Nil when the queue has nothing after this one.
        public var nextTaskTitle: String?

        public init(
            session: FocusSession,
            taskTitle: String,
            difficultyDisplayName: String,
            estimatedDuration: TimeInterval,
            showsCompanion: Bool = true,
            nextTaskTitle: String? = nil
        ) {
            self.session = session
            self.taskTitle = taskTitle
            self.difficultyDisplayName = difficultyDisplayName
            self.estimatedDuration = estimatedDuration
            self.showsCompanion = showsCompanion
            self.nextTaskTitle = nextTaskTitle
        }

        public func remaining(at now: Date = Date()) -> TimeInterval {
            session.remaining(at: now)
        }

        public func progress(at now: Date = Date()) -> Double {
            let total = max(1, session.totalPlanned)
            return session.remaining(at: now) / total
        }

        private enum CodingKeys: String, CodingKey {
            case session
            case taskTitle
            case difficultyDisplayName
            case estimatedDuration
            case showsCompanion
            case nextTaskTitle
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            session = try container.decode(FocusSession.self, forKey: .session)
            taskTitle = try container.decode(String.self, forKey: .taskTitle)
            difficultyDisplayName = try container.decode(String.self, forKey: .difficultyDisplayName)
            estimatedDuration = try container.decode(TimeInterval.self, forKey: .estimatedDuration)
            showsCompanion = try container.decodeIfPresent(Bool.self, forKey: .showsCompanion) ?? true
            nextTaskTitle = try container.decodeIfPresent(String.self, forKey: .nextTaskTitle)
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(session, forKey: .session)
            try container.encode(taskTitle, forKey: .taskTitle)
            try container.encode(difficultyDisplayName, forKey: .difficultyDisplayName)
            try container.encode(estimatedDuration, forKey: .estimatedDuration)
            try container.encode(showsCompanion, forKey: .showsCompanion)
            try container.encodeIfPresent(nextTaskTitle, forKey: .nextTaskTitle)
        }
    }

    public var taskID: UUID

    public init(taskID: UUID) {
        self.taskID = taskID
    }
}
#endif
