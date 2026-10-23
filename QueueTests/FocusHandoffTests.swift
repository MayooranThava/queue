import XCTest
import QueueCore
@testable import Queue

/// One pending focus-end alert, replaced rather than stacked. Start next ends
/// the finished block, starts only the following one, and leaves the rest in order.
@MainActor
final class FocusHandoffTests: XCTestCase {
    func testAlertStaysSingleAndStartNextHandsOff() async throws {
        let harness = try QueueHarness.inMemory()
        let repository = harness.repository
        let first = try await repository.create(title: "A", notes: nil, estimatedDuration: 20 * 60)
        let second = try await repository.create(title: "B", notes: nil, estimatedDuration: 15 * 60)
        let third = try await repository.create(title: "C", notes: nil, estimatedDuration: 10 * 60)

        let started = try await repository.beginFocus(
            taskID: first.id,
            plannedDuration: first.estimatedDuration
        )
        var pending = try await pendingAlert(harness)
        XCTAssertEqual(pending?.taskID, first.id)
        XCTAssertEqual(pending?.sessionID, started.id)
        XCTAssertEqual(try await scheduleCount(harness), 1)

        harness.clock.advance(by: 5 * 60)
        _ = try await repository.pauseFocus(taskID: first.id)
        XCTAssertNil(try await pendingAlert(harness))

        let resumed = try await repository.resumeFocus(taskID: first.id)
        pending = try await pendingAlert(harness)
        XCTAssertEqual(pending?.taskID, first.id)
        XCTAssertEqual(pending?.sessionID, resumed.id)
        let resumedFire = try XCTUnwrap(pending).fireDate

        _ = try await repository.extendFocus(by: 5 * 60)
        pending = try await pendingAlert(harness)
        let extendedFire = try XCTUnwrap(pending).fireDate
        XCTAssertEqual(extendedFire.timeIntervalSince(resumedFire), 5 * 60, accuracy: 2)
        XCTAssertEqual(pending?.taskID, first.id)
        XCTAssertEqual(try await scheduleCount(harness), 3)

        let outcome = try await repository.completeFocus(taskID: first.id)
        XCTAssertNil(try await pendingAlert(harness))
        XCTAssertGreaterThan(outcome.award.awardedXP, 0)
        let total = try harness.storedTotalXP()

        let next = try await repository.beginFocus(
            taskID: second.id,
            plannedDuration: second.estimatedDuration
        )
        pending = try await pendingAlert(harness)
        XCTAssertEqual(pending?.taskID, second.id)
        XCTAssertEqual(pending?.sessionID, next.id)
        XCTAssertNotEqual(pending?.sessionID, started.id)
        XCTAssertEqual(try await scheduleCount(harness), 4)

        let tasks = await repository.tasks()
        XCTAssertEqual(tasks.first { $0.id == first.id }?.status, .completed)
        XCTAssertEqual(tasks.first { $0.id == second.id }?.status, .active)
        XCTAssertEqual(tasks.first { $0.id == third.id }?.status, .queued)
        XCTAssertEqual(await repository.activeQueue().map(\.title), ["B", "C"])
        let sessions = try harness.storedSessions()
        XCTAssertEqual(sessions.map(\.taskID), [second.id])
        XCTAssertEqual(sessions.first?.state, .running)
        XCTAssertEqual(try harness.sourceEventIDs().count, 1)
        XCTAssertEqual(try harness.storedTotalXP(), total)
        XCTAssertNil(await repository.tasks().first {
            $0.id != second.id && ($0.status == .active || $0.status == .paused || $0.status == .expired)
        })
    }

    private func pendingAlert(_ harness: QueueHarness) async throws -> FocusEndAlert? {
        var pending: FocusEndAlert?
        for command in await harness.scheduler.applied {
            switch command {
            case .schedule(let alert):
                pending = alert
            case .cancel:
                pending = nil
            case .leaveScheduledAlert:
                break
            }
        }
        return pending
    }

    private func scheduleCount(_ harness: QueueHarness) async throws -> Int {
        var count = 0
        for command in await harness.scheduler.applied {
            if case .schedule = command {
                count += 1
            }
        }
        return count
    }
}
