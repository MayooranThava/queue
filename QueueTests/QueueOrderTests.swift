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
        var edited = try XCTUnwrap(await repository.tasks().first { $0.id == middle.id })
        edited.title = "B revised"
        edited.notes = "kept"
        edited.estimatedDuration = 20 * 60
        edited.difficulty = .hard
        edited.queuePosition = 0
        try await repository.update(edited)
        XCTAssertEqual(await activeTitles(repository), ["A", "B revised", "C"])

        _ = try await repository.skip(id: first.id)
        XCTAssertEqual(await activeTitles(repository), ["B revised", "C"])
        XCTAssertEqual(await repository.tasks().first { $0.id == first.id }?.status, .skipped)
        XCTAssertNil(await repository.tasks().first { $0.status == .active || $0.status == .paused })

        _ = try await repository.requeue(id: middle.id)
        XCTAssertEqual(await activeTitles(repository), ["C", "B revised"])

        _ = try await repository.create(title: "D", notes: nil, estimatedDuration: 15 * 60)
        XCTAssertEqual(await activeTitles(repository), ["C", "B revised", "D"])

        try await repository.delete(id: middle.id)
        XCTAssertEqual(await activeTitles(repository), ["C", "D"])
        XCTAssertEqual(await repository.tasks().first { $0.id == last.id }?.status, .queued)

        let expected = await activeTitles(repository)
        let reopened = harness.reopenedRepository()
        try await reopened.bootstrapFromStore()
        XCTAssertEqual(await activeTitles(reopened), expected)
        let revised = try XCTUnwrap(await reopened.tasks().first { $0.id == middle.id })
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
