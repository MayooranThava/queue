import Testing
import Foundation
@testable import QueueCore

@Suite("QueueSchedule")
struct QueueScheduleTests {
    @Test("Projects cumulative start times from Now")
    func projectsChain() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let a = QueueTask(title: "A", estimatedDuration: 15 * 60, queuePosition: 0)
        let b = QueueTask(title: "B", estimatedDuration: 10 * 60, queuePosition: 1)
        let c = QueueTask(
            title: "C",
            estimatedDuration: 20 * 60,
            plannedStartAt: now.addingTimeInterval(60 * 60),
            queuePosition: 2
        )
        let starts = QueueSchedule.projectedStarts(orderedActiveTasks: [a, b, c], from: now)
        #expect(starts[a.id] == now)
        #expect(starts[b.id] == now.addingTimeInterval(15 * 60))
        #expect(starts[c.id] == now.addingTimeInterval(60 * 60))
    }

    @Test("Past planned starts clamp to cursor")
    func clampsPastPlans() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let task = QueueTask(
            title: "Late plan",
            estimatedDuration: 10 * 60,
            plannedStartAt: now.addingTimeInterval(-30 * 60)
        )
        let starts = QueueSchedule.projectedStarts(orderedActiveTasks: [task], from: now)
        #expect(starts[task.id] == now)
    }
}
