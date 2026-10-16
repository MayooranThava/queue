import Foundation
import SwiftData
import QueueCore

struct FocusCompletionOutcome: Sendable {
    let task: QueueTask
    let award: RewardAwardResult
}

@MainActor
final class TaskRepository {
    private let context: ModelContext
    private let queueService: TaskQueueService
    private let timerEngine: FocusTimerEngine
    private let rewardEngine: RewardEngine
    private let analytics: AnalyticsClient

    init(
        context: ModelContext,
        queueService: TaskQueueService = TaskQueueService(),
        timerEngine: FocusTimerEngine = FocusTimerEngine(),
        rewardEngine: RewardEngine = RewardEngine(),
        analytics: AnalyticsClient = InMemoryAnalyticsClient()
    ) {
        self.context = context
        self.queueService = queueService
        self.timerEngine = timerEngine
        self.rewardEngine = rewardEngine
        self.analytics = analytics
    }

    func bootstrapFromStore() async throws {
        let taskDescriptor = FetchDescriptor<TaskEntity>(
            sortBy: [SortDescriptor(\.queuePosition), SortDescriptor(\.createdAt)]
        )
        let entities = try context.fetch(taskDescriptor)
        await queueService.replaceAll(entities.map { $0.asDomain() })

        let xpDescriptor = FetchDescriptor<XPTransactionEntity>(
            sortBy: [SortDescriptor(\.timestamp)]
        )
        let xpEntities = try context.fetch(xpDescriptor)
        let transactions = xpEntities.compactMap { $0.asDomain() }
        await rewardEngine.restore(transactions: transactions)
    }

    func tasks() async -> [QueueTask] {
        await queueService.allTasks()
    }

    func activeQueue() async -> [QueueTask] {
        await queueService.activeQueue()
    }

    func create(
        title: String,
        notes: String?,
        estimatedDuration: TimeInterval,
        difficulty: TaskDifficulty = .medium,
        plannedStartAt: Date? = nil
    ) async throws -> QueueTask {
        let task = try await queueService.createTask(
            title: title,
            notes: notes,
            estimatedDuration: estimatedDuration,
            difficulty: difficulty,
            plannedStartAt: plannedStartAt
        )
        context.insert(TaskEntity(from: task))
        try context.save()
        analytics.track(.taskCreated(taskID: task.id))
        return task
    }

    func update(_ task: QueueTask) async throws {
        let updated = try await queueService.updateTask(
            id: task.id,
            title: task.title,
            notes: .some(task.notes),
            estimatedDuration: task.estimatedDuration,
            difficulty: task.difficulty,
            plannedStartAt: .some(task.plannedStartAt),
            scheduledDate: .some(task.scheduledDate),
            category: .some(task.category)
        )
        try upsert(updated)
    }

    func reorder(orderedIDs: [UUID]) async throws {
        try await queueService.reorder(orderedIDs: orderedIDs)
        let queue = await queueService.activeQueue()
        for task in queue {
            try upsert(task)
        }
    }

    /// Starts the domain task and begins a timestamp-backed focus session immediately.
    func beginFocus(taskID: UUID, plannedDuration: TimeInterval) async throws -> FocusSession {
        _ = try await queueService.start(id: taskID)
        let task = try await requireTask(taskID)
        try upsert(task)
        analytics.track(.taskStarted(taskID: taskID))

        if let existing = await timerEngine.currentSession(),
           existing.taskID == taskID,
           existing.state == .running || existing.state == .paused {
            return existing
        }
        // Clear a completed/expired prior session so Start is always immediate.
        if let existing = await timerEngine.currentSession(),
           existing.state == .completed || existing.state == .expired || existing.state == .idle {
            await timerEngine.clear()
        }
        return try await timerEngine.start(taskID: taskID, plannedDuration: plannedDuration)
    }

    func pauseFocus(taskID: UUID) async throws -> FocusSession {
        _ = try await queueService.pause(id: taskID)
        let task = try await requireTask(taskID)
        try upsert(task)
        return try await timerEngine.pause()
    }

    func resumeFocus(taskID: UUID) async throws -> FocusSession {
        _ = try await queueService.resume(id: taskID)
        let task = try await requireTask(taskID)
        try upsert(task)
        return try await timerEngine.resume()
    }

    func extendFocus(by duration: TimeInterval) async throws -> FocusSession {
        let session = try await timerEngine.extend(by: duration)
        analytics.track(.taskExtended(taskID: session.taskID))
        return session
    }

    func completeFocus(taskID: UUID) async throws -> FocusCompletionOutcome {
        let session = try await timerEngine.complete()
        let focusDuration = session.accumulatedActive
        var task = try await queueService.complete(id: taskID, focusDuration: focusDuration)
        try upsert(task)
        analytics.track(.taskCompleted(taskID: taskID))
        analytics.track(.focusSessionCompleted(taskID: taskID))

        let sourceEventID = session.id
        let award = await rewardEngine.awardTaskCompletion(
            sourceEventID: sourceEventID,
            taskID: taskID,
            difficulty: task.difficulty,
            estimatedDuration: task.estimatedDuration,
            actualFocusDuration: focusDuration
        )
        for tx in award.transactions {
            context.insert(XPTransactionEntity(from: tx))
        }
        if let first = award.transactions.first {
            task = try await queueService.attachXPAward(id: taskID, awardID: first.id)
            try upsert(task)
        }
        try context.save()
        return FocusCompletionOutcome(task: task, award: award)
    }

    func undoLastCompletion() async throws -> QueueTask {
        let task = try await queueService.undoLastCompletion()
        try upsert(task)
        return task
    }

    func delete(id: UUID) async throws {
        _ = try await queueService.archive(id: id)
        let descriptor = FetchDescriptor<TaskEntity>(predicate: #Predicate { $0.id == id })
        if let entity = try context.fetch(descriptor).first {
            entity.status = .archived
            entity.modifiedAt = Date()
            try context.save()
        }
    }

    private func requireTask(_ id: UUID) async throws -> QueueTask {
        let all = await queueService.allTasks()
        guard let task = all.first(where: { $0.id == id }) else {
            throw TaskTransitionError.taskNotFound
        }
        return task
    }

    private func upsert(_ task: QueueTask) throws {
        let id = task.id
        let descriptor = FetchDescriptor<TaskEntity>(predicate: #Predicate { $0.id == id })
        if let entity = try context.fetch(descriptor).first {
            entity.apply(task)
        } else {
            context.insert(TaskEntity(from: task))
        }
        try context.save()
    }
}
