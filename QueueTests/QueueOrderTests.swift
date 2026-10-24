import XCTest
import QueueCore
@testable import Queue

/// Add, edit, skip, requeue, and delete keep the relative order of the tasks
/// they do not mean to move. Requeue is the one explicit move, to the bottom.
/// A second repository reads the saved rows, so the order is not only in memory.
@MainActor
final class QueueOrderTests: XCTestCase {
    func testEditsDoNotReorderTheQueueAndTheOrderSurvivesRelaunch() async throws {
        let harness = try QueueHarness.inMemory()
        let repository = harness.repository

        let first = try await repository.create(title: "A", notes: nil, estimatedDuration: 15 * 60)
        let middle = try await repository.create(title: "B", notes: "original", estimatedDuration: 15 * 60)
        let last = try await repository.create(title: "C", notes: nil, estimatedDuration: 15 * 60)
        let storedMiddle = await repository.tasks().first { $0.id == middle.id }
        var edited = try XCTUnwrap(storedMiddle)
        edited.title = "B revised"
        edited.notes = "kept"
        edited.estimatedDuration = 20 * 60
        edited.difficulty = .hard
        edited.queuePosition = 0
        try await repository.update(edited)
        let afterEdit = await activeTitles(repository)
        XCTAssertEqual(afterEdit, ["A", "B revised", "C"])

        _ = try await repository.skip(id: first.id)
        let afterSkip = await activeTitles(repository)
        let skipped = await repository.tasks().first { $0.id == first.id }
        let stillFocusing = await repository.tasks().first { $0.status == .active || $0.status == .paused }
        XCTAssertEqual(afterSkip, ["B revised", "C"])
        XCTAssertEqual(skipped?.status, .skipped)
        XCTAssertNil(stillFocusing)

        _ = try await repository.requeue(id: middle.id)
        let afterRequeue = await activeTitles(repository)
        XCTAssertEqual(afterRequeue, ["C", "B revised"])

        _ = try await repository.create(title: "D", notes: nil, estimatedDuration: 15 * 60)
        let afterAdd = await activeTitles(repository)
        XCTAssertEqual(afterAdd, ["C", "B revised", "D"])

        try await repository.delete(id: middle.id)
        let afterDelete = await activeTitles(repository)
        let remaining = await repository.tasks().first { $0.id == last.id }
        XCTAssertEqual(afterDelete, ["C", "D"])
        XCTAssertEqual(remaining?.status, .queued)

        let expected = await activeTitles(repository)
        let reopened = harness.reopenedRepository()
        try await reopened.bootstrapFromStore()
        let reopenedTitles = await activeTitles(reopened)
        XCTAssertEqual(reopenedTitles, expected)
        let storedRevised = await reopened.tasks().first { $0.id == middle.id }
        let revised = try XCTUnwrap(storedRevised)
        XCTAssertEqual(revised.title, "B revised")
        XCTAssertEqual(revised.notes, "kept")
        XCTAssertEqual(revised.estimatedDuration, 20 * 60)
        XCTAssertEqual(revised.difficulty, .hard)
        XCTAssertEqual(revised.status, .archived)
        XCTAssertFalse(revised.isInActiveQueue)
    }

    private func activeTitles(_ repository: TaskRepository) async -> [String] {
        await repository.activeQueue().map(\.title)
    }
}
