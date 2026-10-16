import Foundation
import SwiftData
import QueueCore

struct FocusCompletionOutcome: Sendable {
    let task: QueueTask
    let award: RewardAwardResult
    let sourceEventID: UUID
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

        try await restoreFocusSessionIfNeeded()
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

    /// Starts or resumes focus. Safe to call when the task is already active/paused.
    func beginFocus(taskID: UUID, plannedDuration: TimeInterval) async throws -> FocusSession {
        if let live = await liveSession(for: taskID) {
            let snapped = await timerEngine.snapshotted() ?? live
            try persistSession(snapped)
            return snapped
        }

        guard let task = await queueService.task(id: taskID) else {
            throw TaskTransitionError.taskNotFound
        }

        switch task.status {
        case .queued:
            _ = try await queueService.start(id: taskID)
            let started = try await requireTask(taskID)
            try upsert(started)
            analytics.track(.taskStarted(taskID: taskID))
            await clearStaleEngineSessionIfNeeded(matching: taskID)
            let session = try await timerEngine.start(
                taskID: taskID,
                plannedDuration: plannedDuration
            )
            try persistSession(session)
            return session

        case .active, .expired:
            // Task already focusing; recreate timer only if memory/session was lost.
            await clearStaleEngineSessionIfNeeded(matching: taskID)
            let session = try await timerEngine.start(
                taskID: taskID,
                plannedDuration: plannedDuration
            )
            try persistSession(session)
            return session

        case .paused:
            await clearStaleEngineSessionIfNeeded(matching: taskID)
            // No persisted segment to resume — start a fresh running segment.
            _ = try await queueService.resume(id: taskID)
            let resumedTask = try await requireTask(taskID)
            try upsert(resumedTask)
            let session = try await timerEngine.start(
                taskID: taskID,
                plannedDuration: plannedDuration
            )
            try persistSession(session)
            return session

        default:
            throw TaskTransitionError.invalidTransition(from: task.status, to: .active)
        }
    }

    func pauseFocus(taskID: UUID) async throws -> FocusSession {
        _ = try await queueService.pause(id: taskID)
        let task = try await requireTask(taskID)
        try upsert(task)
        let session = try await timerEngine.pause()
        try persistSession(session)
        return session
    }

    func resumeFocus(taskID: UUID) async throws -> FocusSession {
        _ = try await queueService.resume(id: taskID)
        let task = try await requireTask(taskID)
        try upsert(task)
        let session = try await timerEngine.resume()
        try persistSession(session)
        return session
    }

    func extendFocus(by duration: TimeInterval) async throws -> FocusSession {
        let session = try await timerEngine.extend(by: duration)
        try persistSession(session)
        analytics.track(.taskExtended(taskID: session.taskID))
        return session
    }

    func evaluateFocusExpiry() async throws -> FocusSession? {
        let session = await timerEngine.evaluateExpiry()
        if let session {
            try persistSession(session)
            if session.state == .expired {
                _ = try? await queueService.expire(id: session.taskID)
                if let task = await queueService.task(id: session.taskID) {
                    try upsert(task)
                }
            }
        }
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
        try persistSession(session)
        try context.save()
        return FocusCompletionOutcome(task: task, award: award, sourceEventID: sourceEventID)
    }

    func undoLastCompletion() async throws -> QueueTask {
        guard let snapshot = await queueService.lastCompleted() else {
            throw TaskTransitionError.taskNotFound
        }

        let sourceEventID = try resolveSourceEventID(for: snapshot)

        let task = try await queueService.undoLastCompletion()
        try upsert(task)

        if let sourceEventID {
            _ = await rewardEngine.revoke(sourceEventID: sourceEventID)
            try deleteXPTransactions(sourceEventID: sourceEventID)
        }

        await timerEngine.clear()
        try clearPersistedSession()
        try context.save()
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

    // MARK: - Session persistence

    private func restoreFocusSessionIfNeeded() async throws {
        let descriptor = FetchDescriptor<FocusSessionEntity>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        guard let entity = try context.fetch(descriptor).first,
              var session = entity.asDomain()
        else { return }

        // Drop terminal sessions left on disk.
        if session.state == .completed || session.state == .idle {
            try clearPersistedSession()
            return
        }

        guard let task = await queueService.task(id: session.taskID),
              task.status == .active || task.status == .paused || task.status == .expired
        else {
            try clearPersistedSession()
            return
        }

        await timerEngine.restore(session)
        if let snapped = await timerEngine.snapshotted() {
            session = snapped
            try persistSession(session)
            if session.state == .expired, task.status != .expired {
                _ = try? await queueService.expire(id: session.taskID)
                if let updated = await queueService.task(id: session.taskID) {
                    try upsert(updated)
                }
            }
        }
    }

    private func liveSession(for taskID: UUID) async -> FocusSession? {
        guard let existing = await timerEngine.currentSession(),
              existing.taskID == taskID,
              existing.state == .running || existing.state == .paused || existing.state == .expired
        else { return nil }
        return existing
    }

    private func clearStaleEngineSessionIfNeeded(matching taskID: UUID) async {
        guard let existing = await timerEngine.currentSession() else { return }
        if existing.taskID != taskID || existing.state == .completed || existing.state == .idle {
            await timerEngine.clear()
        }
    }

    private func persistSession(_ session: FocusSession) throws {
        let descriptor = FetchDescriptor<FocusSessionEntity>()
        if let entity = try context.fetch(descriptor).first {
            entity.apply(session)
        } else {
            context.insert(FocusSessionEntity(session: session))
        }
        try context.save()
        syncWidgetSnapshot(session)
    }

    private func clearPersistedSession() throws {
        let descriptor = FetchDescriptor<FocusSessionEntity>()
        for entity in try context.fetch(descriptor) {
            context.delete(entity)
        }
        try context.save()
        FocusActivityStore.clear()
    }

    /// Publishes timestamps to the App Group so Queue chrome, widgets, and Live Activities stay in sync.
    private func syncWidgetSnapshot(_ session: FocusSession) {
        guard session.state == .running || session.state == .paused || session.state == .expired else {
            FocusActivityStore.clear()
            return
        }
        let taskID = session.taskID
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.id == taskID }
        )
        guard let entity = try? context.fetch(descriptor).first else {
            FocusActivityStore.clear()
            return
        }
        let task = entity.asDomain()
        FocusActivityStore.save(
            FocusWidgetSnapshot(
                taskID: task.id,
                taskTitle: task.title,
                difficultyDisplayName: task.difficulty.displayName,
                estimatedDuration: task.estimatedDuration,
                session: session
            )
        )
    }

    func currentFocusSnapshot() async -> FocusWidgetSnapshot? {
        guard let session = await timerEngine.snapshotted(),
              session.state == .running || session.state == .paused || session.state == .expired,
              let task = await queueService.task(id: session.taskID)
        else {
            if let loaded = FocusActivityStore.load(), loaded.isActivelyTiming {
                return loaded
            }
            return nil
        }
        let snapshot = FocusWidgetSnapshot(
            taskID: task.id,
            taskTitle: task.title,
            difficultyDisplayName: task.difficulty.displayName,
            estimatedDuration: task.estimatedDuration,
            session: session
        )
        FocusActivityStore.save(snapshot)
        return snapshot
    }

    private func resolveSourceEventID(for snapshot: QueueTask) throws -> UUID? {
        guard let awardID = snapshot.xpAwardID else { return nil }
        let descriptor = FetchDescriptor<XPTransactionEntity>(
            predicate: #Predicate { $0.id == awardID }
        )
        return try context.fetch(descriptor).first?.sourceEventID
    }

    private func deleteXPTransactions(sourceEventID: UUID) throws {
        let descriptor = FetchDescriptor<XPTransactionEntity>(
            predicate: #Predicate { $0.sourceEventID == sourceEventID }
        )
        for entity in try context.fetch(descriptor) {
            context.delete(entity)
        }
    }

    private func requireTask(_ id: UUID) async throws -> QueueTask {
        guard let task = await queueService.task(id: id) else {
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
