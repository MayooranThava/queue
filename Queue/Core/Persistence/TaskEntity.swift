import Foundation
import SwiftData
import QueueCore

@Model
final class TaskEntity {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String?
    var estimatedDuration: TimeInterval
    var createdAt: Date
    var scheduledDate: Date?
    var queuePosition: Int
    var statusRaw: String
    var startedAt: Date?
    var completedAt: Date?
    var actualFocusDuration: TimeInterval
    var accumulatedPausedDuration: TimeInterval
    var extensionsData: Data?
    var category: String?
    var calendarEventID: String?
    var xpAwardID: UUID?
    var modifiedAt: Date

    init(from task: QueueTask) {
        self.id = task.id
        self.title = task.title
        self.notes = task.notes
        self.estimatedDuration = task.estimatedDuration
        self.createdAt = task.createdAt
        self.scheduledDate = task.scheduledDate
        self.queuePosition = task.queuePosition
        self.statusRaw = task.status.rawValue
        self.startedAt = task.startedAt
        self.completedAt = task.completedAt
        self.actualFocusDuration = task.actualFocusDuration
        self.accumulatedPausedDuration = task.accumulatedPausedDuration
        self.extensionsData = try? JSONEncoder().encode(task.extensions)
        self.category = task.category
        self.calendarEventID = task.calendarEventID
        self.xpAwardID = task.xpAwardID
        self.modifiedAt = task.modifiedAt
    }

    var status: TaskStatus {
        get { TaskStatus(rawValue: statusRaw) ?? .queued }
        set { statusRaw = newValue.rawValue }
    }

    func apply(_ task: QueueTask) {
        title = task.title
        notes = task.notes
        estimatedDuration = task.estimatedDuration
        createdAt = task.createdAt
        scheduledDate = task.scheduledDate
        queuePosition = task.queuePosition
        statusRaw = task.status.rawValue
        startedAt = task.startedAt
        completedAt = task.completedAt
        actualFocusDuration = task.actualFocusDuration
        accumulatedPausedDuration = task.accumulatedPausedDuration
        extensionsData = try? JSONEncoder().encode(task.extensions)
        category = task.category
        calendarEventID = task.calendarEventID
        xpAwardID = task.xpAwardID
        modifiedAt = task.modifiedAt
    }

    func asDomain() -> QueueTask {
        let extensions: [TimerExtension]
        if let extensionsData,
           let decoded = try? JSONDecoder().decode([TimerExtension].self, from: extensionsData) {
            extensions = decoded
        } else {
            extensions = []
        }
        return QueueTask(
            id: id,
            title: title,
            notes: notes,
            estimatedDuration: estimatedDuration,
            createdAt: createdAt,
            scheduledDate: scheduledDate,
            queuePosition: queuePosition,
            status: status,
            startedAt: startedAt,
            completedAt: completedAt,
            actualFocusDuration: actualFocusDuration,
            accumulatedPausedDuration: accumulatedPausedDuration,
            extensions: extensions,
            category: category,
            calendarEventID: calendarEventID,
            xpAwardID: xpAwardID,
            modifiedAt: modifiedAt
        )
    }
}

@Model
final class UserPreferencesEntity {
    var hasCompletedOnboarding: Bool
    var motivationProfileRaw: String
    var companionVisible: Bool
    var animationIntensityRaw: String
    var autoStartNextTask: Bool
    var dailyGoalCount: Int

    init(
        hasCompletedOnboarding: Bool = false,
        motivationProfile: MotivationProfile = .balanced,
        companionVisible: Bool = true,
        animationIntensity: String = "standard",
        autoStartNextTask: Bool = false,
        dailyGoalCount: Int = 3
    ) {
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.motivationProfileRaw = motivationProfile.rawValue
        self.companionVisible = companionVisible
        self.animationIntensityRaw = animationIntensity
        self.autoStartNextTask = autoStartNextTask
        self.dailyGoalCount = dailyGoalCount
    }

    var motivationProfile: MotivationProfile {
        MotivationProfile(rawValue: motivationProfileRaw) ?? .balanced
    }
}
