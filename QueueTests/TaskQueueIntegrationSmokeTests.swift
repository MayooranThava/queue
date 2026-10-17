import XCTest
import QueueCore

/// Lightweight host-side smoke tests. Prefer `swift test` for QueueCore coverage.
final class TaskQueueIntegrationSmokeTests: XCTestCase {
    func testStateMachineRejectsPauseFromQueued() {
        XCTAssertFalse(TaskStateMachine.canTransition(from: .queued, applying: .pause))
    }

    func testStateMachineAllowsCompleteFromExpired() {
        XCTAssertTrue(TaskStateMachine.canTransition(from: .expired, applying: .complete))
    }

    func testLevelTableIsMonotonic() {
        let xp = LevelTable.standard.map(\.minimumXP)
        XCTAssertEqual(xp, xp.sorted())
    }
}
