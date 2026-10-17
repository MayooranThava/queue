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
}
