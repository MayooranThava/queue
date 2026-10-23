import Testing
import Foundation
@testable import QueueCore

@Suite("TaskQueueService")
struct TaskQueueServiceTests {
    @Test("FIFO ordering on create")
    func fifoOrdering() async throws {
        let clock = ControllableClock()
        let service = TaskQueueService(clock: clock)
        let a = try await service.createTask(title: "A", estimatedDuration: 600)
        let b = try await service.createTask(title: "B", estimatedDuration: 600)
        let c = try await service.createTask(title: "C", estimatedDuration: 600)
        let queue = await service.activeQueue()
        #expect(queue.map(\.title) == ["A", "B", "C"])
        #expect(a.queuePosition == 0)
        #expect(b.queuePosition == 1)
        #expect(c.queuePosition == 2)
    }

    @Test("Single active task invariant")
    func singleActive() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let a = try await service.createTask(title: "A")
        let b = try await service.createTask(title: "B")
        _ = try await service.start(id: a.id)
        await #expect(throws: TaskTransitionError.activeTaskAlreadyExists) {
            try await service.start(id: b.id)
        }
    }

    @Test("Reorder updates positions")
    func reorder() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let a = try await service.createTask(title: "A")
        let b = try await service.createTask(title: "B")
        let c = try await service.createTask(title: "C")
        try await service.reorder(orderedIDs: [c.id, a.id, b.id])
        let queue = await service.activeQueue()
        #expect(queue.map(\.title) == ["C", "A", "B"])
    }

    @Test("Completion and undo")
    func completeAndUndo() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let a = try await service.createTask(title: "A")
        _ = try await service.createTask(title: "B")
        _ = try await service.start(id: a.id)
        let completed = try await service.complete(id: a.id, focusDuration: 120)
        #expect(completed.status == .completed)
        #expect(await service.activeTask() == nil)
        let undone = try await service.undoLastCompletion()
        #expect(undone.status == .queued)
        #expect(undone.title == "A")
    }

    @Test("Complete after timer expiry")
    func completeAfterExpiry() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let a = try await service.createTask(title: "A")
        _ = try await service.start(id: a.id)
        let expired = try await service.expire(id: a.id)
        #expect(expired.status == .expired)
        let completed = try await service.complete(id: a.id, focusDuration: 600)
        #expect(completed.status == .completed)
        #expect(completed.actualFocusDuration == 600)
    }

    @Test("Invalid transition rejected")
    func invalidTransition() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let a = try await service.createTask(title: "A")
        await #expect(throws: TaskTransitionError.self) {
            try await service.pause(id: a.id)
        }
    }

    @Test("Skip and review")
    func skipAndReview() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let a = try await service.createTask(title: "A")
        _ = try await service.start(id: a.id)
        let reviewed = try await service.moveToReview(id: a.id)
        #expect(reviewed.status == .review)
        let requeued = try await service.requeue(id: a.id)
        #expect(requeued.status == .queued)
        _ = try await service.start(id: a.id)
        let skipped = try await service.skip(id: a.id)
        #expect(skipped.status == .skipped)
    }

    @Test("New tasks default to a fifteen minute estimate")
    func defaultEstimateIsFifteenMinutes() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let task = try await service.createTask(title: "Outline")
        #expect(task.estimatedDuration == QueueTask.defaultEstimatedDuration)
        #expect(QueueTask.defaultEstimatedDuration == 15 * 60)
        #expect(QueueTask(title: "Bare").estimatedDuration == 15 * 60)

        let custom = try await service.createTask(title: "Long", estimatedDuration: 25 * 60)
        #expect(custom.estimatedDuration == 25 * 60)
    }

    @Test("Skip removes a queued task and does not start the next one")
    func skipQueuedTask() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let head = try await service.createTask(title: "A")
        _ = try await service.createTask(title: "B")
        let skipped = try await service.skip(id: head.id)
        #expect(skipped.status == .skipped)
        #expect(await service.activeQueue().map(\.title) == ["B"])
        #expect(await service.activeTask() == nil)
    }

    @Test("Skip of the active task does not activate the next task")
    func skipActiveDoesNotPromote() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let head = try await service.createTask(title: "A")
        let next = try await service.createTask(title: "B")
        _ = try await service.start(id: head.id)
        _ = try await service.skip(id: head.id)
        #expect(await service.activeTask() == nil)
        #expect(await service.activeQueue().map(\.title) == ["B"])
        #expect(await service.task(id: next.id)?.status == .queued)
    }

    @Test("Requeue moves a queued task to the bottom and keeps the others in order")
    func requeueQueuedToBottom() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let head = try await service.createTask(title: "A")
        _ = try await service.createTask(title: "B")
        _ = try await service.createTask(title: "C")
        let moved = try await service.requeue(id: head.id)
        #expect(moved.status == .queued)
        let queue = await service.activeQueue()
        #expect(queue.map(\.title) == ["B", "C", "A"])
        #expect(queue.map(\.queuePosition) == [0, 1, 2])
        #expect(await service.activeTask() == nil)
    }

    @Test("Requeue of a later task leaves the active task in place")
    func requeueLeavesActiveTask() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let head = try await service.createTask(title: "A")
        let middle = try await service.createTask(title: "B")
        _ = try await service.createTask(title: "C")
        _ = try await service.start(id: head.id)
        let moved = try await service.requeue(id: middle.id)
        #expect(moved.status == .queued)
        let queue = await service.activeQueue()
        #expect(queue.map(\.title) == ["A", "C", "B"])
        #expect(queue[0].status == .active)
        #expect(await service.activeTask()?.id == head.id)
    }

    @Test("Requeue of the active task is explicit and does not start the next task")
    func requeueActiveTask() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let head = try await service.createTask(title: "A")
        let next = try await service.createTask(title: "B")
        _ = try await service.start(id: head.id)
        let moved = try await service.requeue(id: head.id)
        #expect(moved.status == .queued)
        #expect(await service.activeQueue().map(\.title) == ["B", "A"])
        #expect(await service.activeTask() == nil)
        #expect(await service.task(id: next.id)?.status == .queued)
    }

    @Test("Paused task can return to the bottom without staying in focus")
    func requeuePausedTask() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let head = try await service.createTask(title: "A")
        _ = try await service.createTask(title: "B")
        _ = try await service.start(id: head.id)
        _ = try await service.pause(id: head.id)
        let moved = try await service.requeue(id: head.id)
        #expect(moved.status == .queued)
        #expect(await service.activeTask() == nil)
        #expect(await service.activeQueue().map(\.title) == ["B", "A"])
    }

    @Test("Archive removes queued and focusing tasks, and is terminal")
    func archiveActiveQueueTasks() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let queued = try await service.createTask(title: "A")
        let focusing = try await service.createTask(title: "B")
        let archived = try await service.archive(id: queued.id)
        #expect(archived.status == .archived)
        _ = try await service.start(id: focusing.id)
        let archivedFocus = try await service.archive(id: focusing.id)
        #expect(archivedFocus.status == .archived)
        #expect(await service.activeQueue().isEmpty)
        #expect(await service.activeTask() == nil)
        await #expect(throws: TaskTransitionError.self) {
            try await service.archive(id: focusing.id)
        }
    }

    @Test("Completed tasks still cannot be requeued directly")
    func requeueCompletedRejected() async throws {
        let service = TaskQueueService(clock: ControllableClock())
        let task = try await service.createTask(title: "A")
        _ = try await service.start(id: task.id)
        _ = try await service.complete(id: task.id)
        await #expect(throws: TaskTransitionError.self) {
            try await service.requeue(id: task.id)
        }
    }
}

@Suite("Active task edits")
struct ActiveTaskEditPolicyTests {
    @Test("Focusing states require an explicit end")
    func focusingStates() {
        for status in [TaskStatus.active, .paused, .expired] {
            #expect(ActiveTaskEditPolicy.mustAcknowledgeFocusEnd(status: status, hasLiveSession: false))
        }
    }

    @Test("A live session requires an explicit end even while the task is still queued")
    func liveSessionOnQueuedTask() {
        #expect(ActiveTaskEditPolicy.mustAcknowledgeFocusEnd(status: .queued, hasLiveSession: true))
    }

    @Test("A queued task without a session can change immediately")
    func queuedWithoutSession() {
        #expect(ActiveTaskEditPolicy.mustAcknowledgeFocusEnd(status: .queued, hasLiveSession: false) == false)
        #expect(ActiveTaskEditPolicy.mustAcknowledgeFocusEnd(status: .skipped, hasLiveSession: false) == false)
    }
}
