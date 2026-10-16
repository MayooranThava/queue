import Foundation
import SwiftData
import QueueCore

@MainActor
final class TaskRepository {
    private let context: ModelContext
    private let queueService: TaskQueueService
    private let analytics: AnalyticsClient

    init(
        context: ModelContext,
        queueService: TaskQueueService = TaskQueueService(),
        analytics: AnalyticsClient = InMemoryAnalyticsClient()
    ) {
        self.context = context
        self.queueService = queueService
        self.analytics = analytics
    }

    func bootstrapFromStore() async throws {
        let descriptor = FetchDescriptor<TaskEntity>(
            sortBy: [SortDescriptor(\.queuePosition), SortDescriptor(\.createdAt)]
        )
        let entities = try context.fetch(descriptor)
        await queueService.replaceAll(entities.map { $0.asDomain() })
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
        estimatedDuration: TimeInterval
    ) async throws -> QueueTask {
        let task = try await queueService.createTask(
            title: title,
            notes: notes,
            estimatedDuration: estimatedDuration
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

    func start(_ id: UUID) async throws -> QueueTask {
        let task = try await queueService.start(id: id)
        try upsert(task)
        analytics.track(.taskStarted(taskID: id))
        return task
    }

    func complete(_ id: UUID, focusDuration: TimeInterval) async throws -> QueueTask {
        let task = try await queueService.complete(id: id, focusDuration: focusDuration)
        try upsert(task)
        analytics.track(.taskCompleted(taskID: id))
        return task
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
