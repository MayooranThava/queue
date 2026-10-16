import Foundation

/// Serializes task-queue mutations and enforces FIFO + state-machine rules.
public actor TaskQueueService {
    private var tasks: [UUID: QueueTask] = [:]
    private let clock: any QueueClock
    private var lastCompletedSnapshot: QueueTask?

    public init(clock: any QueueClock = SystemQueueClock(), tasks: [QueueTask] = []) {
        self.clock = clock
        for task in tasks {
            self.tasks[task.id] = task
        }
    }

    public func allTasks() -> [QueueTask] {
        Array(tasks.values).sorted { lhs, rhs in
            if lhs.queuePosition != rhs.queuePosition {
                return lhs.queuePosition < rhs.queuePosition
            }
            return lhs.createdAt < rhs.createdAt
        }
    }

    public func activeQueue() -> [QueueTask] {
        allTasks().filter(\.isInActiveQueue)
    }

    public func activeTask() -> QueueTask? {
        allTasks().first { $0.status == .active || $0.status == .paused || $0.status == .expired }
    }

    public func createTask(
        title: String,
        notes: String? = nil,
        estimatedDuration: TimeInterval = 25 * 60,
        difficulty: TaskDifficulty = .medium,
        plannedStartAt: Date? = nil,
        scheduledDate: Date? = nil,
        category: String? = nil
    ) throws -> QueueTask {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw TaskQueueValidationError.emptyTitle
        }

        let now = clock.now()
        let position = nextQueuePosition()
        let task = QueueTask(
            title: trimmed,
            notes: notes,
            estimatedDuration: estimatedDuration,
            difficulty: difficulty,
            plannedStartAt: plannedStartAt,
            createdAt: now,
            scheduledDate: scheduledDate,
            queuePosition: position,
            status: .queued,
            category: category,
            modifiedAt: now
        )
        tasks[task.id] = task
        return task
    }

    public func updateTask(
        id: UUID,
        title: String? = nil,
        notes: String?? = nil,
        estimatedDuration: TimeInterval? = nil,
        difficulty: TaskDifficulty? = nil,
        plannedStartAt: Date?? = nil,
        scheduledDate: Date?? = nil,
        category: String?? = nil
    ) throws -> QueueTask {
        guard var task = tasks[id] else { throw TaskTransitionError.taskNotFound }
        if let title {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw TaskQueueValidationError.emptyTitle }
            task.title = trimmed
        }
        if let notes { task.notes = notes }
        if let estimatedDuration { task.estimatedDuration = estimatedDuration }
        if let difficulty { task.difficulty = difficulty }
        if let plannedStartAt { task.plannedStartAt = plannedStartAt }
        if let scheduledDate { task.scheduledDate = scheduledDate }
        if let category { task.category = category }
        task.modifiedAt = clock.now()
        tasks[id] = task
        return task
    }

    public func start(id: UUID) throws -> QueueTask {
        if let existing = activeTask(), existing.id != id {
            throw TaskTransitionError.activeTaskAlreadyExists
        }
        return try mutate(id: id, transition: .start) { task, now in
            task.startedAt = task.startedAt ?? now
        }
    }

    public func pause(id: UUID) throws -> QueueTask {
        try mutate(id: id, transition: .pause)
    }

    public func resume(id: UUID) throws -> QueueTask {
        try mutate(id: id, transition: .resume)
    }

    public func complete(id: UUID, focusDuration: TimeInterval = 0) throws -> QueueTask {
        let completed = try mutate(id: id, transition: .complete) { task, now in
            task.completedAt = now
            task.actualFocusDuration = focusDuration
        }
        lastCompletedSnapshot = completed
        return completed
    }

    public func attachXPAward(id: UUID, awardID: UUID) throws -> QueueTask {
        guard var task = tasks[id] else { throw TaskTransitionError.taskNotFound }
        task.xpAwardID = awardID
        task.modifiedAt = clock.now()
        tasks[id] = task
        return task
    }

    public func undoLastCompletion() throws -> QueueTask {
        guard let snapshot = lastCompletedSnapshot,
              var task = tasks[snapshot.id],
              task.status == .completed
        else {
            throw TaskTransitionError.taskNotFound
        }
        if activeTask() != nil {
            throw TaskTransitionError.activeTaskAlreadyExists
        }
        task.status = try TaskStateMachine.apply(from: .completed, transition: .undoComplete)
        task.completedAt = nil
        task.xpAwardID = nil
        task.queuePosition = 0
        task.modifiedAt = clock.now()
        tasks[task.id] = task
        reindexQueue()
        lastCompletedSnapshot = nil
        return tasks[task.id]!
    }

    public func expire(id: UUID) throws -> QueueTask {
        try mutate(id: id, transition: .expire)
    }

    public func moveToReview(id: UUID) throws -> QueueTask {
        try mutate(id: id, transition: .moveToReview)
    }

    public func skip(id: UUID) throws -> QueueTask {
        try mutate(id: id, transition: .skip)
    }

    public func requeue(id: UUID) throws -> QueueTask {
        let position = nextQueuePosition()
        let task = try mutate(id: id, transition: .requeue) { task, _ in
            task.queuePosition = position
            task.completedAt = nil
        }
        reindexQueue()
        return tasks[task.id]!
    }

    public func archive(id: UUID) throws -> QueueTask {
        try mutate(id: id, transition: .archive)
    }

    /// Reorders active-queue tasks to match `orderedIDs`. Terminal tasks are ignored.
    public func reorder(orderedIDs: [UUID]) throws {
        let activeIDs = Set(activeQueue().map(\.id))
        guard Set(orderedIDs) == activeIDs else {
            throw TaskQueueValidationError.invalidReorderSet
        }
        for (index, id) in orderedIDs.enumerated() {
            guard var task = tasks[id] else { continue }
            if !task.isInActiveQueue {
                throw TaskTransitionError.cannotReorderTerminalTask
            }
            task.queuePosition = index
            task.modifiedAt = clock.now()
            tasks[id] = task
        }
    }

    public func replaceAll(_ newTasks: [QueueTask]) {
        tasks = Dictionary(uniqueKeysWithValues: newTasks.map { ($0.id, $0) })
        lastCompletedSnapshot = newTasks
            .filter { $0.status == .completed }
            .max(by: { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) })
    }

    // MARK: - Private

    private func mutate(
        id: UUID,
        transition: TaskTransition,
        update: ((inout QueueTask, Date) -> Void)? = nil
    ) throws -> QueueTask {
        guard var task = tasks[id] else { throw TaskTransitionError.taskNotFound }
        let newStatus = try TaskStateMachine.apply(from: task.status, transition: transition)
        let now = clock.now()
        task.status = newStatus
        update?(&task, now)
        task.modifiedAt = now
        tasks[id] = task
        return task
    }

    private func nextQueuePosition() -> Int {
        (activeQueue().map(\.queuePosition).max() ?? -1) + 1
    }

    private func reindexQueue() {
        let ordered = activeQueue()
        for (index, task) in ordered.enumerated() {
            var copy = task
            copy.queuePosition = index
            copy.modifiedAt = clock.now()
            tasks[copy.id] = copy
        }
    }
}

public enum TaskQueueValidationError: Error, Equatable, Sendable {
    case emptyTitle
    case invalidReorderSet
}
