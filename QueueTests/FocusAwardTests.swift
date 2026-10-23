import XCTest
import QueueCore
@testable import Queue

/// Start, pause, and +5 award nothing. Done awards XP for that session once.
/// The widget and the Lock Screen run the same commands through the repository.
/// Reopening the saved store cannot award the finished session again.
@MainActor
final class FocusAwardTests: XCTestCase {
    func testStartPauseExtendAndDoneAwardXPOnce() async throws {
        let harness = try QueueHarness.inMemory()
        let task = try await harness.repository.create(
            title: "Write",
            notes: nil,
            estimatedDuration: 15 * 60
        )

        _ = try await harness.repository.beginFocus(taskID: task.id, plannedDuration: 15 * 60)
        _ = try await harness.repository.pauseFocus(taskID: task.id)
        _ = try await harness.repository.resumeFocus(taskID: task.id)
        _ = try await harness.repository.extendFocus(by: 5 * 60)
        XCTAssertEqual(try harness.storedTotalXP(), 0)

        let outcome = try await harness.repository.completeFocus(taskID: task.id)
        XCTAssertGreaterThan(outcome.award.awardedXP, 0)
        XCTAssertEqual(outcome.task.status, .completed)
        let total = try harness.storedTotalXP()
        XCTAssertEqual(total, outcome.award.totalXP)
        XCTAssertEqual(try harness.sourceEventIDs(), Set([outcome.sourceEventID]))
        try await assertNoFurtherAward(taskID: task.id, on: harness.repository, reading: harness, expected: total)
    }

    func testWidgetAndLockScreenCommandsAwardXPOnce() async throws {
        let harness = try QueueHarness.inMemory()
        let repository = harness.repository
        let calls = RepositoryFocusCalls(repository: repository)
        let head = try await repository.create(title: "Now", notes: nil, estimatedDuration: 15 * 60)
        let following = try await repository.create(title: "Later", notes: nil, estimatedDuration: 10 * 60)

        let queue = QueueWidgetSnapshot(
            now: QueueWidgetNow(
                id: head.id,
                title: head.title,
                duration: head.estimatedDuration,
                difficulty: head.difficulty
            ),
            upNext: [
                QueueWidgetUpcoming(id: following.id, title: following.title, duration: following.estimatedDuration)
            ],
            doneToday: 0,
            plannedToday: 2,
            minutesFocusedToday: 0,
            updatedAt: harness.clock.now()
        )
        let start = try XCTUnwrap(WidgetFocusRouting.command(for: .startNext, queue: queue, focus: nil))
        try await WidgetFocusIntentPerformer.perform(start, using: calls)
        XCTAssertEqual(try harness.storedTotalXP(), 0)

        try await perform(.pauseOrResume, on: harness, using: calls)
        XCTAssertEqual(try harness.storedTotalXP(), 0)
        try await perform(.pauseOrResume, on: harness, using: calls)
        try await perform(.extendFiveMinutes, on: harness, using: calls)
        XCTAssertEqual(try harness.storedTotalXP(), 0)
        XCTAssertEqual(await repository.activeQueue().map(\.title), ["Now", "Later"])

        try await perform(.complete, on: harness, using: calls)
        let total = try harness.storedTotalXP()
        XCTAssertGreaterThan(total, 0)
        XCTAssertEqual(try harness.sourceEventIDs().count, 1)
        XCTAssertEqual(await repository.activeQueue().map(\.title), ["Later"])
        XCTAssertEqual(await repository.tasks().first { $0.id == following.id }?.status, .queued)

        let widget = harness.reopenedRepository()
        try await widget.bootstrapFromStore()
        try await assertNoFurtherAward(taskID: head.id, on: widget, reading: harness, expected: total)
    }

    func testCompletionDoesNotAwardAgainAfterRelaunch() async throws {
        let harness = try QueueHarness.inMemory()
        let task = try await harness.repository.create(title: "Write", notes: nil, estimatedDuration: 15 * 60)
        _ = try await harness.repository.beginFocus(taskID: task.id, plannedDuration: 15 * 60)
        let outcome = try await harness.repository.completeFocus(taskID: task.id)
        let total = try harness.storedTotalXP()
        let events = Set([outcome.sourceEventID])
        XCTAssertEqual(try harness.sourceEventIDs(), events)

        let reopened = harness.reopenedRepository()
        try await reopened.bootstrapFromStore()
        XCTAssertEqual(try harness.storedTotalXP(), total)
        XCTAssertEqual(try harness.sourceEventIDs(), events)
        try await assertNoFurtherAward(taskID: task.id, on: reopened, reading: harness, expected: total)
    }

    func testElapsedFocusSurvivesRelaunchAndStillAwardsOnce() async throws {
        let harness = try QueueHarness.inMemory()
        let task = try await harness.repository.create(title: "Read", notes: nil, estimatedDuration: 10 * 60)
        _ = try await harness.repository.beginFocus(taskID: task.id, plannedDuration: 10 * 60)
        harness.clock.advance(by: 4 * 60)

        let restored = harness.reopenedRepository()
        try await restored.bootstrapFromStore()
        let snapshot = try XCTUnwrap(await restored.currentFocusSnapshot())
        XCTAssertEqual(snapshot.taskID, task.id)
        XCTAssertEqual(snapshot.session.state, .running)
        XCTAssertEqual(snapshot.session.remaining(at: harness.clock.now()), 6 * 60, accuracy: 1)

        let outcome = try await restored.completeFocus(taskID: task.id)
        XCTAssertGreaterThan(outcome.award.awardedXP, 0)
        let total = try harness.storedTotalXP()
        XCTAssertEqual(try harness.sourceEventIDs().count, 1)
        try await assertNoFurtherAward(taskID: task.id, on: restored, reading: harness, expected: total)
    }

    private func perform(
        _ action: WidgetFocusAction,
        on harness: QueueHarness,
        using calls: RepositoryFocusCalls
    ) async throws {
        let focus = await harness.repository.currentFocusSnapshot()
        let command = try XCTUnwrap(WidgetFocusRouting.command(for: action, queue: nil, focus: focus))
        try await WidgetFocusIntentPerformer.perform(command, using: calls)
    }

    private func assertNoFurtherAward(
        taskID: UUID,
        on repository: TaskRepository,
        reading harness: QueueHarness,
        expected: Int
    ) async throws {
        do {
            _ = try await repository.completeFocus(taskID: taskID)
        } catch {
            // The session is already finished, or the reopened store has none.
        }
        XCTAssertEqual(try harness.storedTotalXP(), expected)
        XCTAssertEqual(try harness.sourceEventIDs().count, 1)
    }
}
