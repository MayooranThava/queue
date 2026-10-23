import Foundation
import SwiftData
import QueueCore

enum TaskRepositoryError: LocalizedError {
    case focusEndNotAcknowledged

    var errorDescription: String? {
        switch self {
        case .focusEndNotAcknowledged:
            return "This task is in focus. End that session before skipping, moving, or deleting it."
        }
    }
}

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
    private let focusAlertSync: FocusEndNotificationSync
    private let notificationAuthorizer: any FocusNotificationAuthorizing

    init(
        context: ModelContext,
        queueService: TaskQueueService = TaskQueueService(),
        timerEngine: FocusTimerEngine = FocusTimerEngine(),
        rewardEngine: RewardEngine = RewardEngine(),
        analytics: AnalyticsClient = InMemoryAnalyticsClient(),
        focusNotifications: any FocusEndNotificationScheduling = NoOpFocusEndNotificationScheduler(),
        notificationAuthorizer: any FocusNotificationAuthorizing = SilentFocusNotificationAuthorizer()
    ) {
        self.context = context
        self.queueService = queueService
        self.timerEngine = timerEngine
        self.rewardEngine = rewardEngine
        self.analytics = analytics
        self.focusAlertSync = FocusEndNotificationSync(scheduler: focusNotifications)
        self.notificationAuthorizer = notificationAuthorizer
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

        let preferenceDescriptor = FetchDescriptor<UserPreferencesEntity>()
        if let profile = try context.fetch(preferenceDescriptor).first?.motivationProfile {
            await rewardEngine.setProfile(profile)
        }

        try await restoreFocusSessionIfNeeded()
        await publishQueueSnapshot()
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
        await publishQueueSnapshot()
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
        await publishQueueSnapshot()
    }

    func reorder(orderedIDs: [UUID]) async throws {
        try await queueService.reorder(orderedIDs: orderedIDs)
        let queue = await queueService.activeQueue()
        for task in queue {
            try upsert(task)
        }
        await publishQueueSnapshot()
    }

    /// Starts or resumes focus. Safe to call when the task is already active/paused.
    func beginFocus(taskID: UUID, plannedDuration: TimeInterval) async throws -> FocusSession {
        if let live = await liveSession(for: taskID) {
            let snapped = await timerEngine.snapshotted() ?? live
            try persistSession(snapped)
            await publishFocusAlert(snapped, prompt: true)
            await publishQueueSnapshot()
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
            await publishFocusAlert(session, prompt: true)
            await publishQueueSnapshot()
            return session

        case .active, .expired:
            // Task already focusing; recreate timer only if memory/session was lost.
            await clearStaleEngineSessionIfNeeded(matching: taskID)
            let session = try await timerEngine.start(
                taskID: taskID,
                plannedDuration: plannedDuration
            )
            try persistSession(session)
            await publishFocusAlert(session, prompt: true)
            await publishQueueSnapshot()
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
            await publishFocusAlert(session, prompt: true)
            await publishQueueSnapshot()
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
        await publishFocusAlert(session, prompt: false)
        await publishQueueSnapshot()
        return session
    }

    func resumeFocus(taskID: UUID) async throws -> FocusSession {
        _ = try await queueService.resume(id: taskID)
        let task = try await requireTask(taskID)
        try upsert(task)
        let session = try await timerEngine.resume()
        try persistSession(session)
        await publishFocusAlert(session, prompt: true)
        await publishQueueSnapshot()
        return session
    }

    func extendFocus(by duration: TimeInterval) async throws -> FocusSession {
        let session = try await timerEngine.extend(by: duration)
        try persistSession(session)
        analytics.track(.taskExtended(taskID: session.taskID))
        await publishFocusAlert(session, prompt: true)
        await publishQueueSnapshot()
        return session
    }

    func evaluateFocusExpiry() async throws -> FocusSession? {
        let session = await timerEngine.evaluateExpiry()
        if let session {
            try persistSession(session)
            await publishFocusAlert(session, prompt: false)
            if session.state == .expired {
                _ = try? await queueService.expire(id: session.taskID)
                if let task = await queueService.task(id: session.taskID) {
                    try upsert(task)
                }
            }
        }
        await publishQueueSnapshot()
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
        try await mergePersistedAwards(sourceEventID: sourceEventID)
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
        await publishFocusAlert(session, prompt: false)
        await publishQueueSnapshot()
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
        await syncFocusAlert(nil)
        try context.save()
        await publishQueueSnapshot()
        return task
    }

    /// Removes the task from the active queue by archiving it.
    /// Pass `endFocus: true` only after the user agrees to stop a running session.
    func delete(id: UUID, endFocus: Bool = false) async throws {
        try await ensureFocusChangeIsExplicit(for: id, endFocus: endFocus)
        let task = try await queueService.archive(id: id)
        try upsert(task)
        try await clearFocusSession(for: id)
        await publishQueueSnapshot()
    }

    /// Drops the task out of the active queue. It can be requeued later.
    func skip(id: UUID, endFocus: Bool = false) async throws -> QueueTask {
        try await ensureFocusChangeIsExplicit(for: id, endFocus: endFocus)
        let task = try await queueService.skip(id: id)
        try upsert(task)
        try await clearFocusSession(for: id)
        await publishQueueSnapshot()
        return task
    }

    /// Places the task at the bottom of the stack. Other tasks keep their order.
    func requeue(id: UUID, endFocus: Bool = false) async throws -> QueueTask {
        try await ensureFocusChangeIsExplicit(for: id, endFocus: endFocus)
        let task = try await queueService.requeue(id: id)
        for item in await queueService.activeQueue() {
            try upsert(item)
        }
        if await queueService.task(id: id)?.isInActiveQueue != true {
            try upsert(task)
        }
        try await clearFocusSession(for: id)
        await publishQueueSnapshot()
        return await queueService.task(id: id) ?? task
    }

    func hasLiveFocusSession(for taskID: UUID) async -> Bool {
        if let session = await timerEngine.currentSession(),
           session.taskID == taskID,
           session.state == .running || session.state == .paused || session.state == .expired {
            return true
        }
        if let snapshot = FocusActivityStore.load(),
           snapshot.taskID == taskID,
           snapshot.isActivelyTiming {
            return true
        }
        return false
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
            await syncFocusAlert(nil)
            return
        }

        guard let task = await queueService.task(id: session.taskID),
              task.status == .active || task.status == .paused || task.status == .expired
        else {
            try clearPersistedSession()
            await syncFocusAlert(nil)
            return
        }

        await timerEngine.restore(session)
        if let snapped = await timerEngine.snapshotted() {
            session = snapped
            try persistSession(session)
            await publishFocusAlert(session, prompt: false)
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
        let taskID = session.taskID
        let descriptor = FetchDescriptor<TaskEntity>(
            predicate: #Predicate { $0.id == taskID }
        )
        guard let entity = try? context.fetch(descriptor).first,
              let snapshot = FocusWidgetSnapshot.live(task: entity.asDomain(), session: session)
        else {
            FocusActivityStore.clear()
            return
        }
        FocusActivityStore.save(snapshot)
    }

    func currentFocusSnapshot() async -> FocusWidgetSnapshot? {
        if let session = await timerEngine.snapshotted(),
           session.state == .running || session.state == .paused || session.state == .expired {
            if let task = await queueService.task(id: session.taskID),
               let snapshot = FocusWidgetSnapshot.live(task: task, session: session) {
                FocusActivityStore.save(snapshot)
                await syncFocusAlert(session, taskTitle: task.title)
                return snapshot
            }
            // Keep the alert tied to the in-memory session even if the row lookup missed.
            await syncFocusAlert(session)
            return nil
        }
        if let loaded = FocusActivityStore.load(), loaded.isActivelyTiming {
            await syncFocusAlert(loaded.session, taskTitle: loaded.taskTitle)
            return loaded
        }
        await syncFocusAlert(nil)
        return nil
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

    private func ensureFocusChangeIsExplicit(for taskID: UUID, endFocus: Bool) async throws {
        guard let task = await queueService.task(id: taskID) else {
            throw TaskTransitionError.taskNotFound
        }
        let sessionLive = await hasLiveFocusSession(for: taskID)
        let needsAcknowledgement = ActiveTaskEditPolicy.mustAcknowledgeFocusEnd(
            status: task.status,
            hasLiveSession: sessionLive
        )
        if needsAcknowledgement && !endFocus {
            throw TaskRepositoryError.focusEndNotAcknowledged
        }
    }

    /// Stops the timer only when it belongs to this task. A session for a different task stays up.
    private func clearFocusSession(for taskID: UUID) async throws {
        if let current = await timerEngine.currentSession(), current.taskID == taskID {
            await timerEngine.clear()
            FocusActivityStore.clear()
            try clearPersistedSession()
            await syncFocusAlert(nil)
            return
        }
        guard FocusActivityStore.load()?.taskID == taskID else { return }
        FocusActivityStore.clear()
        let descriptor = FetchDescriptor<FocusSessionEntity>()
        if let entity = try context.fetch(descriptor).first, entity.taskID == taskID {
            try clearPersistedSession()
            if await timerEngine.currentSession() == nil {
                await syncFocusAlert(nil)
            }
        }
    }

    /// Keeps the pending focus-end alert aligned with the session.
    /// Permission is requested only when a user action is about to run the timer.
    private func publishFocusAlert(_ session: FocusSession, prompt: Bool) async {
        if prompt {
            await authorizeAlertsIfNeeded(session)
        }
        await syncFocusAlert(session)
    }

    private func authorizeAlertsIfNeeded(_ session: FocusSession) async {
        guard session.state == .running else { return }
        let status = await notificationAuthorizer.authorizationStatus()
        guard FocusNotificationPermissionPolicy.shouldRequest(
            status: status,
            reason: .focusStartOrResume
        ) else { return }
        _ = await notificationAuthorizer.requestAuthorization()
    }

    private func syncFocusAlert(_ session: FocusSession?, taskTitle: String? = nil) async {
        let title: String
        if let taskTitle {
            title = taskTitle
        } else if let session, let task = await queueService.task(id: session.taskID) {
            title = task.title
        } else {
            title = ""
        }
        await focusAlertSync.sync(session: session, taskTitle: title, now: Date())
    }

    /// Writes the up-next snapshot the widget reads, then reloads its timelines.
    func publishQueueSnapshot(now: Date = Date()) async {
        let tasks = await queueService.allTasks()
        let snapshot = QueueWidgetSnapshotBuilder.make(tasks: tasks, at: now)
        QueueActivityStore.save(snapshot)
        QueueWidgetReload.reload()
    }

    /// Replaces the in-memory queue, timer, and XP ledger with a store another process just wrote.
    func applyExternalSnapshot(
        tasks: [QueueTask],
        session: FocusSession?,
        transactions: [XPTransaction]
    ) async throws {
        for entity in try context.fetch(FetchDescriptor<TaskEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<FocusSessionEntity>()) {
            context.delete(entity)
        }
        for entity in try context.fetch(FetchDescriptor<XPTransactionEntity>()) {
            context.delete(entity)
        }
        try context.save()

        for task in tasks {
            context.insert(TaskEntity(from: task))
        }
        let liveSession = liveSnapshotSession(session)
        if let liveSession {
            context.insert(FocusSessionEntity(session: liveSession))
        }
        for transaction in transactions {
            context.insert(XPTransactionEntity(from: transaction))
        }
        try context.save()

        await queueService.replaceAll(tasks)
        await rewardEngine.restore(transactions: transactions)
        await timerEngine.clear()
        if let liveSession {
            await timerEngine.restore(liveSession)
            if let snapped = await timerEngine.snapshotted() {
                try persistSession(snapped)
                await syncFocusAlert(snapped)
            }
        } else {
            FocusActivityStore.clear()
            await syncFocusAlert(nil)
        }
        await publishQueueSnapshot()
    }

    /// Pulls awards another process already saved so a second complete does not insert them again.
    private func mergePersistedAwards(sourceEventID: UUID) async throws {
        let descriptor = FetchDescriptor<XPTransactionEntity>(
            predicate: #Predicate { $0.sourceEventID == sourceEventID }
        )
        let existing = try context.fetch(descriptor).compactMap { $0.asDomain() }
        guard !existing.isEmpty else { return }
        var ledger = await rewardEngine.transactions()
        let known = Set(ledger.map(\.id))
        for transaction in existing where !known.contains(transaction.id) {
            ledger.append(transaction)
        }
        await rewardEngine.restore(transactions: ledger)
    }

    private func liveSnapshotSession(_ session: FocusSession?) -> FocusSession? {
        guard let session else { return nil }
        switch session.state {
        case .running, .paused, .expired:
            return session
        case .idle, .completed:
            return nil
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
