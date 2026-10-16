import Foundation

public struct TimerExtension: Codable, Sendable, Equatable, Identifiable {
    public let id: UUID
    public let duration: TimeInterval
    public let createdAt: Date

    public init(id: UUID = UUID(), duration: TimeInterval, createdAt: Date) {
        self.id = id
        self.duration = duration
        self.createdAt = createdAt
    }
}

public struct QueueTask: Identifiable, Codable, Sendable, Equatable {
    public var id: UUID
    public var title: String
    public var notes: String?
    public var estimatedDuration: TimeInterval
    public var createdAt: Date
    public var scheduledDate: Date?
    public var queuePosition: Int
    public var status: TaskStatus
    public var startedAt: Date?
    public var completedAt: Date?
    public var actualFocusDuration: TimeInterval
    public var accumulatedPausedDuration: TimeInterval
    public var extensions: [TimerExtension]
    public var category: String?
    public var calendarEventID: String?
    public var xpAwardID: UUID?
    public var modifiedAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String? = nil,
        estimatedDuration: TimeInterval = 25 * 60,
        createdAt: Date = Date(),
        scheduledDate: Date? = nil,
        queuePosition: Int = 0,
        status: TaskStatus = .queued,
        startedAt: Date? = nil,
        completedAt: Date? = nil,
        actualFocusDuration: TimeInterval = 0,
        accumulatedPausedDuration: TimeInterval = 0,
        extensions: [TimerExtension] = [],
        category: String? = nil,
        calendarEventID: String? = nil,
        xpAwardID: UUID? = nil,
        modifiedAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.estimatedDuration = estimatedDuration
        self.createdAt = createdAt
        self.scheduledDate = scheduledDate
        self.queuePosition = queuePosition
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.actualFocusDuration = actualFocusDuration
        self.accumulatedPausedDuration = accumulatedPausedDuration
        self.extensions = extensions
        self.category = category
        self.calendarEventID = calendarEventID
        self.xpAwardID = xpAwardID
        self.modifiedAt = modifiedAt
    }

    public var isInActiveQueue: Bool {
        switch status {
        case .queued, .active, .paused, .expired:
            return true
        case .completed, .review, .skipped, .archived:
            return false
        }
    }
}
