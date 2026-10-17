import Testing
import Foundation
@testable import QueueCore

@Suite("FocusTimerEngine")
struct FocusTimerEngineTests {
    @Test("Start pause resume extend expire")
    func lifecycle() async throws {
        let clock = ControllableClock()
        let engine = FocusTimerEngine(clock: clock)
        let taskID = UUID()
        var session = try await engine.start(taskID: taskID, plannedDuration: 60)
        #expect(session.state == .running)
        #expect(await engine.remaining() == 60)

        clock.advance(by: 20)
        session = try await engine.pause()
        #expect(session.state == .paused)
        #expect(await engine.remaining() == 40)

        clock.advance(by: 100)
        session = try await engine.resume()
        #expect(await engine.remaining() == 40)

        session = try await engine.extend(by: 30)
        #expect(await engine.remaining() == 70)

        clock.advance(by: 70)
        let expired = await engine.evaluateExpiry()
        #expect(expired?.state == .expired)
        #expect(await engine.remaining() == 0)
    }

    @Test("Restore after relaunch")
    func restore() async throws {
        let clock = ControllableClock()
        let start = clock.now()
        let taskID = UUID()
        let persisted = FocusSession(
            taskID: taskID,
            sessionStart: start,
            segmentStart: start,
            plannedDuration: 120,
            state: .running
        )
        clock.advance(by: 45)
        let engine = FocusTimerEngine(clock: clock)
        await engine.restore(persisted)
        #expect(await engine.remaining() == 75)
    }

    @Test("Prevents duplicate completion and dual sessions")
    func invariants() async throws {
        let clock = ControllableClock()
        let engine = FocusTimerEngine(clock: clock)
        _ = try await engine.start(taskID: UUID(), plannedDuration: 30)
        await #expect(throws: FocusTimerError.sessionAlreadyActive) {
            try await engine.start(taskID: UUID(), plannedDuration: 30)
        }
        _ = try await engine.complete()
        await #expect(throws: FocusTimerError.alreadyCompleted) {
            try await engine.complete()
        }
    }

    @Test("Complete succeeds after expiry")
    func completeAfterExpiry() async throws {
        let clock = ControllableClock()
        let engine = FocusTimerEngine(clock: clock)
        _ = try await engine.start(taskID: UUID(), plannedDuration: 30)
        clock.advance(by: 30)
        let expired = await engine.evaluateExpiry()
        #expect(expired?.state == .expired)
        let completed = try await engine.complete()
        #expect(completed.state == .completed)
        #expect(completed.accumulatedActive == 30)
    }
}
