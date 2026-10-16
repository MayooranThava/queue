import Testing
import Foundation
@testable import QueueCore

@Suite("Focus widget snapshot")
struct FocusWidgetSnapshotTests {
    @Test("Remaining and progress derive from session timestamps")
    func derivesFromTimestamps() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let session = FocusSession(
            taskID: UUID(),
            sessionStart: start,
            segmentStart: start,
            plannedDuration: 600,
            accumulatedActive: 120,
            state: .running
        )
        let snapshot = FocusWidgetSnapshot(
            taskID: session.taskID,
            taskTitle: "Ship widgets",
            difficultyDisplayName: "Medium",
            estimatedDuration: 600,
            session: session,
            updatedAt: start
        )

        let at = start.addingTimeInterval(60)
        #expect(snapshot.remaining(at: at) == 420)
        #expect(abs(snapshot.progress(at: at) - 0.7) < 0.001)
        #expect(snapshot.isActivelyTiming)
    }

    @Test("Clock formatting pads minutes and seconds")
    func clockFormatting() {
        #expect(FocusTimerFormatting.clock(125) == "02:05")
        #expect(FocusTimerFormatting.clock(0) == "00:00")
        #expect(FocusTimerFormatting.spoken(125) == "2 minutes 5 seconds")
    }

    @Test("Activity store round-trips through UserDefaults")
    func storeRoundTrip() {
        FocusActivityStore.clear()
        let start = Date()
        let session = FocusSession(
            taskID: UUID(),
            sessionStart: start,
            segmentStart: start,
            plannedDuration: 300,
            state: .paused
        )
        let snapshot = FocusWidgetSnapshot(
            taskID: session.taskID,
            taskTitle: "Pause check",
            difficultyDisplayName: "Easy",
            estimatedDuration: 300,
            session: session
        )
        FocusActivityStore.save(snapshot)
        let loaded = FocusActivityStore.load()
        #expect(loaded?.taskTitle == "Pause check")
        #expect(loaded?.session.state == .paused)
        FocusActivityStore.clear()
        #expect(FocusActivityStore.load() == nil)
    }
}
